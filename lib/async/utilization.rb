# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "utilization/version"
require_relative "utilization/schema"
require_relative "utilization/interface"
require_relative "utilization/observer"

module Async
	module Utilization
		# Increment a field value, optionally with a block that auto-decrements.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter field [Symbol] The field name to increment.
		# @yield Optional block - if provided, decrements the field after the block completes.
		# @returns [Integer] The new value of the field.
		def self.increment(...)
			Interface.instance.increment(...)
		end
		
		# Decrement a field value.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter field [Symbol] The field name to decrement.
		# @returns [Integer] The new value of the field.
		def self.decrement(...)
			Interface.instance.decrement(...)
		end
		
		# Set a field value.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter field [Symbol] The field name to set.
		# @parameter value [Numeric] The value to set.
		def self.set(...)
			Interface.instance.set(...)
		end
		
		# Set the observer for utilization metrics.
		#
		# When an observer is set, it is notified of all current values
		# so it can sync its state. The observer must implement `set(field, value)`.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter observer [#set] The observer to set.
		def self.observer=(observer)
			Interface.instance.observer = observer
		end
	end
end
