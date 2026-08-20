# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "sus/fixtures/console/null_logger"
require "sus/fixtures/temporary_directory_context"
require "async/utilization"

describe Async::Utilization::SegmentAllocator do
	include Sus::Fixtures::Console::NullLogger
	include Sus::Fixtures::TemporaryDirectoryContext
	
	let(:path) {File.join(root, "utilization.shm")}
	let(:page_size) {IO::Buffer::PAGE_SIZE}
	let(:schema) do
		Async::Utilization::Schema.build(
			requests_total: :u64,
			requests_active: :u32,
		)
	end
	
	it "allocates, reads, and reuses segments" do
		allocator = subject.new(path, size: page_size, segment_size: page_size)
		
		first_offset = allocator.allocate(:first, [])
		expect(first_offset).to be == 0
		expect(allocator.allocation(:first)).to have_keys(offset: be == 0, schema: be == [])
		
		allocator.update_schema(:first, schema.to_a)
		observer = Async::Utilization::Observer.open(schema, path, page_size, first_offset)
		observer.buffer.set_value(:u64, 0, 12)
		observer.buffer.set_value(:u32, 8, 3)
		
		expect(allocator.read(:first)).to be == {requests_total: 12, requests_active: 3}
		
		allocator.free(:first)
		expect(allocator.read(:first)).to be_nil
		expect(allocator.allocate(:second, schema.to_a)).to be == first_offset
	ensure
		observer&.buffer&.free
		allocator&.close
	end
	
	it "preserves existing observer mappings when resizing" do
		allocator = subject.new(path, size: page_size, segment_size: page_size)
		first_offset = allocator.allocate(:first, schema.to_a)
		observer = Async::Utilization::Observer.open(schema, path, page_size, first_offset)
		
		observer.buffer.set_value(:u64, 0, 42)
		expect(allocator.read(:first)[:requests_total]).to be == 42
		
		second_offset = allocator.allocate(:second, schema.to_a)
		expect(second_offset).to be == page_size
		expect(allocator.size).to be == page_size * 2
		
		observer.buffer.set_value(:u64, 0, 99)
		expect(allocator.read(:first)[:requests_total]).to be == 99
	ensure
		observer&.buffer&.free
		allocator&.close
	end
	
	it "only replaces an existing file when requested" do
		original = subject.new(path, size: page_size, segment_size: page_size)
		original.resize(page_size * 2)
		
		existing_file = File.open(path, "rb")
		original_size = existing_file.size
		original.close
		
		expect do
			subject.new(path, size: page_size, segment_size: page_size)
		end.to raise_exception(Errno::EEXIST)
		
		replacement = subject.new(path, size: page_size, segment_size: page_size, replace: true)
		expect(replacement.size).to be == page_size
		expect(existing_file.size).to be == original_size
	ensure
		original&.close
		replacement&.close
		existing_file&.close
	end
end
