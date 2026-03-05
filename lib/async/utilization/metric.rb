# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Async
	module Utilization
		# A cached metric reference that avoids hash lookups on the fast path.
		#
		# This class caches all the details needed to write directly to shared memory,
		# including the buffer, offset, and type. When the observer changes, the cache
		# is invalidated and rebuilt on the next access.
		class Metric
			# Initialize a new metric.
			#
			# @parameter name [Symbol] The field name for this metric.
			# @parameter registry [Registry] The registry instance to use.
			def initialize(name, registry)
				@name = name.to_sym
				@registry = registry
				@value = 0
				@cache_valid = false
				@cached_field_info = nil
				@cached_buffer = nil
				@guard = Mutex.new
			end
			
			# @attribute [Symbol] The field name for this metric.
			attr :name
			
			# @attribute [Numeric] The current value of this metric.
			attr :value
			
			# @attribute [Mutex] The mutex for thread safety.
			attr :guard
			
			# Invalidate the cached field information.
			#
			# Called when the observer changes to force cache rebuild.
			def invalidate
				@cache_valid = false
				@cached_field_info = nil
				@cached_buffer = nil
			end
			
			# Increment the metric value, optionally with a block that auto-decrements.
			#
			# Uses the fast path (direct buffer write) when cache is valid and observer is available.
			#
			# @yield Optional block - if provided, decrements the field after the block completes.
			# @returns [Integer] The new value of the field.
			def increment(&block)
				@guard.synchronize do
					@value += 1
					write_direct(@value)
				end
				
				if block_given?
					begin
						yield
					ensure
						# Decrement after block completes
						decrement
					end
				end
				
				@value
			end
			
			# Decrement the metric value.
			#
			# Uses the fast path (direct buffer write) when cache is valid and observer is available.
			#
			# @returns [Integer] The new value of the field.
			def decrement
				@guard.synchronize do
					@value -= 1
					write_direct(@value)
				end
				
				@value
			end
			
			# Set the metric value.
			#
			# Uses the fast path (direct buffer write) when cache is valid and observer is available.
			#
			# @parameter value [Numeric] The value to set.
			def set(value)
				@guard.synchronize do
					@value = value
					write_direct(@value)
				end
			end

			protected
			
			# Check if the cache is valid and rebuild if necessary.
			#
			# Always attempts to build the cache if it's invalid. Returns true if cache
			# is now valid (observer exists, field is in schema, and buffer is available), false otherwise.
			#
			# @returns [bool] True if cache is valid, false otherwise.
			def ensure_cache_valid!
				unless @cache_valid
					if observer = @registry.observer
						if field = observer.schema[@name]
							if buffer = observer.buffer
								@cached_field_info = field
								@cached_buffer = buffer
							end
						end
					end

					# Once we've validated the cache, even if there was no observer or buffer, we mark it as valid, so that we don't try to revalidate it again:
					@cache_valid = true
				end
			end
			
			# Write directly to the cached buffer if available.
			#
			# This is the fast path that avoids hash lookups. Always ensures cache is valid
			# first. If there's no observer or buffer, silently does nothing.
			#
			# @parameter value [Numeric] The value to write.
			# @returns [Boolean] Whether the write succeeded.
			def write_direct(value)
				self.ensure_cache_valid!

				if @cached_buffer
					@cached_buffer.set_value(@cached_field_info.type, @cached_field_info.offset, value)
				end

				return true
			rescue => error
				# If write fails, log warning but don't invalidate cache
				# The error might be transient, and invalidating would force hash lookups
				Console.warn(self, "Failed to write metric value!", metric: {name: @name, value: value}, exception: error)
				
				return false
			end
		end
	end
end
