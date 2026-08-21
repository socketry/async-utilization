# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "sus/fixtures/console/null_logger"
require "sus/fixtures/temporary_directory_context"
require "async/utilization"

describe Async::Utilization::SegmentStore do
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
		store = subject.open(path, size: page_size, segment_size: page_size)
		
		first_offset = store.allocate(:first, [])
		expect(first_offset).to be == 0
		expect(store.allocation(:first)).to have_keys(offset: be == 0, schema: be == [])
		
		store.update_schema(:first, schema.to_a)
		observer = Async::Utilization::Observer.open(schema, path, page_size, first_offset)
		observer.buffer.set_value(:u64, 0, 12)
		observer.buffer.set_value(:u32, 8, 3)
		
		expect(store.read(:first)).to be == {requests_total: 12, requests_active: 3}
		
		store.free(:first)
		expect(store.read(:first)).to be_nil
		expect(store.allocate(:second, schema.to_a)).to be == first_offset
	ensure
		observer&.buffer&.free
		store&.close
	end
	
	it "preserves existing observer mappings when resizing" do
		store = subject.open(path, size: page_size, segment_size: page_size)
		first_offset = store.allocate(:first, schema.to_a)
		observer = Async::Utilization::Observer.open(schema, path, page_size, first_offset)
		
		observer.buffer.set_value(:u64, 0, 42)
		expect(store.read(:first)[:requests_total]).to be == 42
		
		second_offset = store.allocate(:second, schema.to_a)
		expect(second_offset).to be == page_size
		expect(store.size).to be == page_size * 2
		
		observer.buffer.set_value(:u64, 0, 99)
		expect(store.read(:first)[:requests_total]).to be == 99
	ensure
		observer&.buffer&.free
		store&.close
	end
	
	it "returns nil when automatic resizing fails" do
		store = subject.open(path, size: page_size, segment_size: page_size)
		store.allocate(:first, schema.to_a)
		
		expect(store).to receive(:resize).and_return(false)
		expect(store.allocate(:second, schema.to_a)).to be_nil
	ensure
		store&.close
	end
	
	it "skips fields that cannot be read" do
		store = subject.open(path, size: page_size, segment_size: page_size)
		store.allocate(:worker, [[:invalid, :invalid, 0]])
		
		expect(store.read(:worker)).to be == {}
	ensure
		store&.close
	end
	
	it "reports resize failures" do
		store = subject.open(path, size: page_size, segment_size: page_size)
		file = store.instance_variable_get(:@file)
		
		expect(file).to receive(:truncate).and_raise(IOError, "Failed to resize")
		expect(store.resize(page_size * 2)).to be_falsey
	ensure
		store&.close
	end
	
	it "only replaces an existing file when requested" do
		original = subject.open(path, size: page_size, segment_size: page_size)
		original.resize(page_size * 2)
		
		existing_file = File.open(path, "rb")
		original_size = existing_file.size
		original.close
		
		expect do
			subject.open(path, size: page_size, segment_size: page_size)
		end.to raise_exception(Errno::EEXIST)
		
		replacement = subject.open(path, size: page_size, segment_size: page_size, replace: true)
		expect(replacement.size).to be == page_size
		expect(existing_file.size).to be == original_size
	ensure
		original&.close
		replacement&.close
		existing_file&.close
	end
	
	it "validates configuration before replacing an existing file" do
		File.write(path, "existing")
		
		[
			[{size: 0}, "Size must be a positive integer!"],
			[{segment_size: 0}, "Segment size must be a positive integer!"],
			[{size: page_size, segment_size: page_size * 2}, "Segment size must not exceed size!"],
			[{growth_factor: 1}, "Growth factor must be greater than 1!"],
		].each do |options, message|
			expect do
				subject.open(path, replace: true, **options)
			end.to raise_exception(ArgumentError, message: be == message)
			
			expect(File.read(path)).to be == "existing"
		end
	end
	
	it "closes the store after yielding it" do
		file = nil
		
		result = subject.open(path, size: page_size, segment_size: page_size) do |store|
			file = store.instance_variable_get(:@file)
			expect(file.closed?).to be_falsey
			:result
		end
		
		expect(result).to be == :result
		expect(file.closed?).to be_truthy
	end
	
	it "closes the file when mapping fails" do
		file = File.open(path, "w+bx")
		File.unlink(path)
		
		expect(File).to receive(:open).with(path, "w+bx").and_return(file)
		expect(IO::Buffer).to receive(:map).with(file, page_size).and_raise(IOError, "Failed to map")
		
		expect do
			subject.open(path, size: page_size, segment_size: page_size)
		end.to raise_exception(IOError, message: be == "Failed to map")
		
		expect(file.closed?).to be_truthy
	end
	
	it "releases acquired resources when initialization fails" do
		file = File.open(path, "w+bx")
		File.unlink(path)
		buffer = IO::Buffer.new(page_size)
		
		expect(File).to receive(:open).with(path, "w+bx").and_return(file)
		expect(IO::Buffer).to receive(:map).with(file, page_size).and_return(buffer)
		expect(subject).to receive(:new).and_raise(IOError, "Failed to initialize")
		
		expect do
			subject.open(path, size: page_size, segment_size: page_size)
		end.to raise_exception(IOError, message: be == "Failed to initialize")
		
		expect(file.closed?).to be_truthy
		expect(buffer.null?).to be_truthy
	end
end
