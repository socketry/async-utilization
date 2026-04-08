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

- {ruby Async::Utilization::Registry}: Holds your metrics and optional observer; create one explicitly and pass it to the code that records utilization.
- {ruby Async::Utilization::Schema}: Defines the binary layout for serialization.
- {ruby Async::Utilization::Observer}: Writes metrics to shared memory using the schema.
- {ruby Async::Utilization::Metric}: The handle you call `increment`, `set`, `track`, etc. on; obtained from the registry.

## Basic Usage

Create a registry, then get a {ruby Async::Utilization::Metric} per field and use it as the main API:

```ruby
require "async/utilization"

registry = Async::Utilization::Registry.new

total_requests = registry.metric(:total_requests)
active_requests = registry.metric(:active_requests)

total_requests.increment

# Track an operation (increment before block, decrement after):
active_requests.track do
	# Handle request - automatically decrements when block completes
end
```

Metrics are tracked in memory and can be accessed programmatically. However, for inter-process communication (e.g., with a supervisor process), you'll want to use a shared memory observer.

## Using metrics from your own objects

Assign the handle from the registry to an instance variable (or replace it when you switch to a different registry):

```ruby
@total_requests = registry.metric(:total_requests)
```

Each call to `registry.metric(:field)` returns the **same** cached instance for that field. Setting `registry.observer = …` updates every metric the registry already holds, so you normally keep using the same handle. Fetch a new metric only when you use a different registry or a different field name.

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

registry = Async::Utilization::Registry.new

# Attach observer - metrics on this registry write to shared memory
registry.observer = observer

total_requests = registry.metric(:total_requests)
total_requests.increment
```

The observer automatically handles page alignment requirements for memory mapping, so you can use any segment size and offset. The supervisor process can then read these metrics from shared memory to aggregate utilization across all workers.
