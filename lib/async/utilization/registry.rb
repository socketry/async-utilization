# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "console"

module Async
	module Utilization
		# Registry for emitting utilization metrics.
		#
		# The registry tracks values directly and notifies a registered observer
		# when values change. The observer (like Observer) can write to its backend.
		#
		# Registries should be explicitly created and passed to components that need them.
		# In service contexts, registries are typically created via the evaluator and
		# shared across components within the same service instance.
		#
		# When an observer is added, it is immediately notified of all current values
		# so it can sync its state. When values change, the observer is notified.
		#
		# @example Create a registry and emit metrics:
		# 	registry = Async::Utilization::Registry.new
		# 	
		# 	# Emit metrics - values tracked in registry
		# 	registry.increment(:total_requests)
		# 	registry.track(:active_requests) do
		# 		# Handle request - auto-decrements when block completes
		# 	end
		# 	
		# 	# Add shared memory observer when supervisor connects
		# 	# Observer will be notified of all current values automatically
		# 	schema = Async::Utilization::Schema.build(
		# 		total_requests: :u64,
		# 		active_requests: :u32
		# 	)
		# 	observer = Async::Utilization::Observer.open(schema, "/path/to/shm", 4096, 0)
		# 	registry.observer = observer
		class Registry
			
			# Initialize a new registry.
			def initialize
				@observer = nil
				@metrics = {}
				
				@guard = Mutex.new
			end
			
			# @attribute [Object | Nil] The registered observer.
			attr :observer
			
			# @attribute [Mutex] The mutex for thread safety.
			attr :guard
			
			# Get the current values for all metrics.
			#
			# @returns [Hash] Hash mapping field names to their current values.
			def values
				@metrics.transform_values do |metric|
					metric.guard.synchronize{metric.value}
				end
			end
			
			# Set the observer for the registry.
			#
			# When an observer is set, it is notified of all current metric values
			# so it can sync its state. The observer must implement `set(field, value)`.
			# All cached metrics are invalidated when the observer changes.
			#
			# @parameter observer [#set] The observer to set.
			def observer=(observer)
				@guard.synchronize do
					@observer = observer
					
					# Invalidate all cached metrics with new observer (or nil)
					@metrics.each_value do |metric|
						metric.observer = observer
					end
					
					Console.info(self, "Observer assigned", observer: observer, metric_count: @metrics.size)
				end
				
			end
			
			# Set a field value.
			#
			# Delegates to the metric instance for the given field.
			#
			# @parameter field [Symbol] The field name to set.
			# @parameter value [Numeric] The value to set.
			def set(field, value)
				metric(field).set(value)
			end
			
			# Increment a field value.
			#
			# Delegates to the metric instance for the given field.
			#
			# @parameter field [Symbol] The field name to increment.
			# @returns [Integer] The new value of the field.
			def increment(field)
				metric(field).increment
			end
			
			# Track an operation: increment before the block, decrement after it completes.
			#
			# Delegates to the metric instance for the given field.
			#
			# @parameter field [Symbol] The field name to track.
			# @yield The operation to track.
			# @returns [Object] The block's return value.
			def track(field, &block)
				metric(field).track(&block)
			end
			
			# Decrement a field value.
			#
			# Delegates to the metric instance for the given field.
			#
			# @parameter field [Symbol] The field name to decrement.
			# @returns [Integer] The new value of the field.
			def decrement(field)
				metric(field).decrement
			end
			
			# Get a cached metric reference for a field.
			#
			# Returns a {Metric} instance that caches all details needed for fast writes.
			# Metrics are cached per field and invalidated when the observer changes.
			#
			# @parameter field [Symbol] The field name to get a metric for.
			# @returns [Metric] A metric instance for the given field.
			def metric(field)
				field = field.to_sym
				
				@guard.synchronize do
					@metrics[field] ||= Metric.new(field)
				end
			end
		end
	end
end
