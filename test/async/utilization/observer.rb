# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "sus/fixtures/console/captured_logger"
require "sus/fixtures/temporary_directory_context"
require "async/utilization"
require "fileutils"

describe Async::Utilization::Observer do
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
	end
	
	it "can create an observer from a file" do
		expect(observer).to be_a(Async::Utilization::Observer)
		expect(observer.schema).to be == schema
	end
	
	it "can write values to shared memory" do
		observer.set(:total_requests, 42)
		observer.set(:active_requests, 5)
		
		# Read back from file to verify
		buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
		expect(buffer.get_value(:u64, 0)).to be == 42
		expect(buffer.get_value(:u32, 8)).to be == 5
	end
	
	with "non-page-aligned offsets" do
		let(:file_size) {IO::Buffer::PAGE_SIZE * 2}
		let(:offset) {100}  # Not page-aligned
		
		it "handles non-page-aligned offsets" do
			observer.set(:total_requests, 100)
			observer.set(:active_requests, 20)
			
			# Read back from file at the correct offset
			buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
			expect(buffer.get_value(:u64, offset)).to be == 100
			expect(buffer.get_value(:u32, offset + 8)).to be == 20
		end
	end
	
	it "ignores fields not in schema" do
		# Should not raise an error
		observer.set(:unknown_field, 999)
		
		# Verify nothing was written
		buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
		expect(buffer.get_value(:u64, 0)).to be == 0
	end
	
	with "page-aligned offsets" do
		let(:file_size) {page_size * 2}
		let(:segment_size) {page_size}
		
		it "handles page-aligned offsets without slicing" do
			expect(observer).to be_a(Async::Utilization::Observer)
			observer.set(:total_requests, 123)
			
			# Verify value was written
			buffer = IO::Buffer.map(File.open(shm_path, "r+b"), file_size, 0)
			expect(buffer.get_value(:u64, 0)).to be == 123
		end
	end
	
	it "handles errors gracefully when setting values" do
		# Create an invalid buffer that will cause an error
		# We'll mock the buffer to raise an error
		buffer = observer.instance_variable_get(:@buffer)
		expect(buffer).to receive(:set_value).and_raise(IOError, "Buffer error")
		
		# Should not raise, but log a warning
		observer.set(:total_requests, 42)
		
		# Assert that a warning was logged
		expect_console.to have_logged(
			severity: be == :warn,
			subject: be_a(Async::Utilization::Observer),
			message: be == "Failed to set field in shared memory!"
		)
	end
end
