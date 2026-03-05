# Getting Started

This guide explains how to get started with `async-utilization` to track high-performance utilization metrics for Async services using shared memory.

## Installation

Add the gem to your project:

```bash
$ bundle add async-utilization
```

## Core Concepts

`async-utilization` provides a convenient interface for tracking utilization metrics that can be synchronized to shared memory for inter-process communication.

The key components are:

- {ruby Async::Utilization::Interface}: Thread-local singleton for emitting metrics.
- {ruby Async::Utilization::Schema}: Defines the binary layout for serialization.
- {ruby Async::Utilization::Observer}: Writes metrics to shared memory using the schema.
- {ruby Async::Utilization::Metric}: Caches metric value and fast path for direct buffer updates.

## Basic Usage

The recommended way to use `async-utilization` is to get a cached metric reference and use it:

```ruby
require "async/utilization"

# Get metrics:
total_requests = Async::Utilization.metric(:total_requests)
active_requests = Async::Utilization.metric(:active_requests)

# Increment a metric:
total_requests.increment

# Increment with auto-decrement:
active_requests.increment do
	# Handle request - automatically decrements when block completes
end
```

Metrics are tracked in memory and can be accessed programmatically. However, for inter-process communication (e.g., with a supervisor process), you'll want to use a shared memory observer.

## With Shared Memory Observer

When you need to share metrics with other processes (like a supervisor monitoring worker health), you can set up a shared memory observer:

```ruby
require "async/utilization"

# Define schema - specifies field names and types
schema = Async::Utilization::Schema.build(
	total_requests: :u64,
	active_requests: :u32
)

# Create observer for shared memory
# The observer maps a region of shared memory and writes metrics there
observer = Async::Utilization::Observer.open(
	schema,
	"/path/to/shared_memory.shm",
	512,  # segment size
	0     # offset
)

# Set observer - metrics will now be written to shared memory
Async::Utilization.observer = observer

# All metrics are written directly to shared memory:
total_requests = Async::Utilization.metric(:total_requests)
total_requests.increment
```

The observer automatically handles page alignment requirements for memory mapping, so you can use any segment size and offset. The supervisor process can then read these metrics from shared memory to aggregate utilization across all workers.
