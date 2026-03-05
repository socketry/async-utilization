# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "utilization/version"
require_relative "utilization/schema"
require_relative "utilization/interface"
require_relative "utilization/observer"
require_relative "utilization/metric"

# @namespace
module Async
	# Provides high-performance utilization metrics for Async services using shared memory.
	#
	# This module provides a convenient interface for tracking utilization metrics
	# that can be synchronized to shared memory for inter-process communication.
	# Each thread gets its own instance of the underlying {Interface}, providing
	# thread-local behavior.
	#
	# See the {file:guides/getting-started/readme.md Getting Started} guide for usage examples.
	module Utilization
		# Set the observer for utilization metrics.
		#
		# When an observer is set, it is notified of all current metric values
		# so it can sync its state. The observer must implement `set(field, value)`.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter observer [#set] The observer to set.
		def self.observer=(observer)
			Interface.instance.observer = observer
		end
		
		# Get a cached metric reference for a field.
		#
		# Returns a {Metric} instance that caches all details needed for fast writes
		# to shared memory, avoiding hash lookups on the fast path.
		#
		# This is the recommended way to access metrics for optimal performance.
		#
		# Delegates to the thread-local {Interface} instance.
		#
		# @parameter field [Symbol] The field name to get a metric for.
		# @returns [Metric] A metric instance for the given field.
		# @example
		#   current_requests = Async::Utilization.metric(:current_requests)
		#   current_requests.increment
		#   current_requests.increment do
		#     # Handle request - auto-decrements when block completes
		#   end
		def self.metric(field)
			Interface.instance.metric(field)
		end
	end
end
