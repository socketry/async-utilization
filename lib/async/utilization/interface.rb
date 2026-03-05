# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "thread/local"

module Async
	module Utilization
		# Interface for emitting utilization metrics.
		#
		# The interface tracks values directly and notifies a registered observer
		# when values change. The observer (like Observer) can write to its backend.
		#
		# Each thread gets its own instance of the interface, providing
		# thread-local behavior through the thread-local gem.
		#
		# When an observer is added, it is immediately notified of all current values
		# so it can sync its state. When values change, the observer is notified.
		#
		# @example
		#   interface = Async::Utilization::Interface.new
		#   
		#   # Emit metrics - values tracked in interface
		#   interface.increment(:total_requests)
		#   interface.increment(:active_requests) do
		#     # Handle request - auto-decrements when block completes
		#   end
		#   
		#   # Add shared memory observer when supervisor connects
		#   # Observer will be notified of all current values automatically
		#   schema = Async::Utilization::Schema.build(
		#     total_requests: :u64,
		#     active_requests: :u32
		#   )
		#   observer = Async::Utilization::Observer.open(schema, "/path/to/shm", 4096, 0)
		#   interface.observer = observer
		class Interface
			extend Thread::Local
			
			# Initialize a new interface.
			def initialize
				@observer = nil
				@values = Hash.new(0)
				
				@guard = Mutex.new
			end
			
			# @attribute [Object | Nil] The registered observer.
			attr :observer
			
			# @attribute [Hash] The current values for all fields.
			attr :values
			
			# Set the observer for the interface.
			#
			# When an observer is set, it is notified of all current values
			# so it can sync its state. The observer must implement `set(field, value)`.
			#
			# @parameter observer [#set] The observer to set.
			def observer=(observer)
				@guard.synchronize do
					@observer = observer
					
					@values.each do |field, value|
						observer.set(field, value)
					end
				end
			end
			
			# Set a field value.
			#
			# Updates the interface's value and notifies the registered observer.
			#
			# @parameter field [Symbol] The field name to set.
			# @parameter value [Numeric] The value to set.
			def set(field, value)
				field = field.to_sym
				
				@guard.synchronize do
					@values[field] = value
					@observer&.set(field, value)
				end
			end
			
			# Increment a field value, optionally with a block that auto-decrements.
			#
			# Updates the interface's value and notifies the registered observer.
			#
			# @parameter field [Symbol] The field name to increment.
			# @yield Optional block - if provided, decrements the field after the block completes.
			# @returns [Integer] The new value of the field.
			def increment(field)
				field = field.to_sym
				
				new_value = nil
				@guard.synchronize do
					new_value = @values[field] + 1
					@values[field] = new_value
					@observer&.set(field, new_value)
				end
				
				if block_given?
					begin
						yield
					ensure
						# Decrement after block completes
						decrement(field)
					end
				end
				
				new_value
			end
			
			# Decrement a field value.
			#
			# Updates the interface's value and notifies the registered observer.
			#
			# @parameter field [Symbol] The field name to decrement.
			# @returns [Integer] The new value of the field.
			def decrement(field)
				field = field.to_sym
				
				new_value = nil
				@guard.synchronize do
					new_value = @values[field] - 1
					@values[field] = new_value
					@observer&.set(field, new_value)
				end
				
				new_value
			end
		end
	end
end
