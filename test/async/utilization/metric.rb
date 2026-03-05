# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "sus/fixtures/console/captured_logger"
require "sus/fixtures/temporary_directory_context"
require "async/utilization"

describe Async::Utilization::Metric do
	include Sus::Fixtures::Console::CapturedLogger
	include Sus::Fixtures::TemporaryDirectoryContext
	
	let(:shm_path) {File.join(root, "test.shm")}
	let(:schema) do
		Async::Utilization::Schema.build(
			total_requests: :u64,
			active_requests: :u32
		)
	end
	
	let(:page_size) {IO::Buffer::PAGE_SIZE}
	let(:segment_size) {512}
	let(:file_size) {[segment_size, page_size].max}
	let(:offset) {0}
	
	let(:observer) do
		Async::Utilization::Observer.open(schema, shm_path, segment_size, offset)
	end
	
	before do
		File.open(shm_path, "w+b") do |file|
			file.truncate(file_size)
		end
		
		# Reset the registry to ensure clean state between tests
		registry = Async::Utilization::Registry.instance
		registry.instance_variable_set(:@values, Hash.new(0))
		registry.instance_variable_set(:@metrics, {})
		registry.instance_variable_set(:@observer, nil)
	end
	
	it "can create a metric from a field name" do
		metric = Async::Utilization.metric(:total_requests)
		
		expect(metric).to be_a(Async::Utilization::Metric)
		expect(metric.name).to be == :total_requests
	end
	
	it "can increment a metric" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		value = metric.increment
		expect(value).to be == 1
		expect(metric.value).to be == 1
		
		value = metric.increment
		expect(value).to be == 2
		expect(metric.value).to be == 2
	end
	
	it "can decrement a metric" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		metric.increment
		metric.increment
		
		value = metric.decrement
		expect(value).to be == 1
		expect(metric.value).to be == 1
	end
	
	it "can set a metric value" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		metric.set(42)
		expect(metric.value).to be == 42
		
		metric.set(100)
		expect(metric.value).to be == 100
	end
	
	it "can increment with auto-decrement block" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:active_requests)
		
		metric.increment do
			expect(metric.value).to be == 1
		end
		
		expect(metric.value).to be == 0
	end
	
	it "decrements even if block raises an error" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:active_requests)
		
		begin
			metric.increment do
				raise "Test error"
			end
		rescue => error
			expect(error.message).to be == "Test error"
		end
		
		expect(metric.value).to be == 0
	end
	
	it "writes directly to shared memory when observer is set" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		metric.set(42)
		
		# Read back from file to verify
		buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
		expect(buffer.get_value(:u64, 0)).to be == 42
	end
	
	it "invalidates cache when observer changes" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		# Set a value - cache should be built
		metric.set(10)
		expect(metric.value).to be == 10
		
		# Create a new observer with different schema
		new_schema = Async::Utilization::Schema.build(
			total_requests: :u64,
			active_requests: :u32
		)
		new_shm_path = File.join(root, "test2.shm")
		File.open(new_shm_path, "w+b"){|f| f.truncate(file_size)}
		new_observer = Async::Utilization::Observer.open(new_schema, new_shm_path, segment_size, 0)
		
		# Change observer - cache should be invalidated
		Async::Utilization.observer = new_observer
		
		# Set a new value - cache should be rebuilt
		metric.set(20)
		expect(metric.value).to be == 20
		
		# Verify it was written to the new shared memory file
		buffer = IO::Buffer.map(File.open(new_shm_path, "r+b"), file_size, 0)
		expect(buffer.get_value(:u64, 0)).to be == 20
	end
	
	it "works without an observer" do
		metric = Async::Utilization.metric(:total_requests)
		
		# Should work fine without observer (uses fallback path)
		metric.increment
		expect(metric.value).to be == 1
		
		metric.set(5)
		expect(metric.value).to be == 5
		
		# Set observer and verify it works with fast path
		Async::Utilization.observer = observer
		metric.set(10)
		expect(metric.value).to be == 10
	end
	
	it "returns the same metric instance for the same field" do
		metric1 = Async::Utilization.metric(:total_requests)
		metric2 = Async::Utilization.metric(:total_requests)
		
		expect(metric1).to be == metric2
	end
	
	it "falls back to observer.set when write_direct fails" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		# Force cache to be invalid by invalidating it
		metric.invalidate
		
		# Set a value - should fall back to observer.set
		metric.set(42)
		expect(metric.value).to be == 42
		
		# Verify it was written to shared memory
		buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
		expect(buffer.get_value(:u64, 0)).to be == 42
	end
	
	it "handles write errors gracefully" do
		Async::Utilization.observer = observer
		metric = Async::Utilization.metric(:total_requests)
		
		# Set a value first to build the cache
		metric.set(10)
		
		# Verify cache is built
		expect(metric.instance_variable_get(:@cache_valid)).to be == true
		cached_buffer = metric.instance_variable_get(:@cached_buffer)
		
		# Create an invalid buffer that will raise an error
		invalid_buffer = Object.new
		def invalid_buffer.set_value(type, offset, value)
			raise IOError, "Buffer error"
		end
		
		metric.instance_variable_set(:@cached_buffer, invalid_buffer)
		
		# Should not raise, but log warning and keep cache valid
		metric.set(42)
		expect(metric.value).to be == 42
		
		# Cache should remain valid (not invalidated on error)
		expect(metric.instance_variable_get(:@cache_valid)).to be == true
		
		# Assert that a warning was logged
		expect_console.to have_logged(
			severity: be == :warn,
			subject: be_a(Async::Utilization::Metric),
			message: be == "Failed to write metric value!"
		)
	end
end
