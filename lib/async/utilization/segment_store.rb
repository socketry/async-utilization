# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "console"

module Async
	module Utilization
		# Represents a shared memory segment store for utilization data.
		#
		# Stores fixed-size segments in a shared memory file, associates each
		# segment with a utilization schema, and reads the resulting values.
		class SegmentStore
			# Open a shared memory segment store.
			#
			# @parameter path [String] The path to the shared memory file.
			# @parameter size [Integer] The initial size of the shared memory file.
			# @parameter segment_size [Integer] The size of each allocation segment.
			# @parameter growth_factor [Integer | Float] The factor used to grow the file when all segments are allocated.
			# @parameter replace [Boolean] Whether to replace an existing file at the given path.
			# @yields {|store| ...} The store, which is closed after the block completes.
			# 	@parameter store [SegmentStore] The opened store.
			# @returns [SegmentStore | Object] The store, or the value returned by the block.
			# @raises [ArgumentError] If the store configuration is invalid.
			# @raises [Errno::EEXIST] If the path already exists and `replace` is `false`.
			def self.open(path, size: IO::Buffer::PAGE_SIZE * 8, segment_size: 512, growth_factor: 2, replace: false)
				raise ArgumentError, "Size must be a positive integer!" unless size.is_a?(Integer) && size > 0
				raise ArgumentError, "Segment size must be a positive integer!" unless segment_size.is_a?(Integer) && segment_size > 0
				raise ArgumentError, "Segment size must not exceed size!" if segment_size > size
				raise ArgumentError, "Growth factor must be greater than 1!" unless growth_factor.is_a?(Numeric) && growth_factor.real? && growth_factor > 1
				
				if replace
					begin
						File.unlink(path)
					rescue Errno::ENOENT
						# The file does not need to be replaced:
					end
				end
				
				file = File.open(path, "w+bx")
				buffer = nil
				
				begin
					file.truncate(size)
					buffer = IO::Buffer.map(file, size)
					store = new(file, buffer, size: size, segment_size: segment_size, growth_factor: growth_factor)
				rescue
					buffer&.free
					file.close
					raise
				end
				
				return store unless block_given?
				
				begin
					yield store
				ensure
					store.close
				end
			end
			
			# Initialize the shared memory segment store.
			#
			# @parameter file [File] The open shared memory file.
			# @parameter buffer [IO::Buffer] The mapped shared memory buffer.
			# @parameter size [Integer] The initial size of the shared memory file.
			# @parameter segment_size [Integer] The size of each allocation segment.
			# @parameter growth_factor [Integer | Float] The factor used to grow the file when all segments are allocated.
			def initialize(file, buffer, size:, segment_size:, growth_factor:)
				@file = file
				@buffer = buffer
				@size = size
				@segment_size = segment_size
				@growth_factor = growth_factor
				
				@allocations = {}
				@free_list = []
				
				(0...(@size / @segment_size)).each do |segment_index|
					@free_list << (segment_index * @segment_size)
				end
			end
			
			# Allocate a segment for the given key.
			#
			# The shared memory file is automatically resized if no segments are available.
			#
			# @parameter key [Object] The key used to identify the allocation.
			# @parameter schema [Array] The `[key, type, offset]` tuples describing the data layout.
			# @returns [Integer | Nil] The offset into the shared memory file, or `nil` if allocation fails.
			def allocate(key, schema)
				if @free_list.empty?
					unless resize(@size * @growth_factor)
						return nil
					end
				end
				
				offset = @free_list.shift
				@allocations[key] = {offset: offset, schema: schema}
				
				return offset
			end
			
			# Free the segment allocated to the given key.
			#
			# @parameter key [Object] The key used to identify the allocation.
			def free(key)
				if allocation = @allocations.delete(key)
					@free_list << allocation[:offset]
				end
			end
			
			# Get the allocation information for the given key.
			#
			# @parameter key [Object] The key used to identify the allocation.
			# @returns [Hash | Nil] The allocation offset and schema, or `nil` if the key is not allocated.
			def allocation(key)
				@allocations[key]
			end
			
			# @attribute [Integer] The current size of the shared memory file.
			attr :size
			
			# Update the schema for an existing allocation.
			#
			# @parameter key [Object] The key used to identify the allocation.
			# @parameter schema [Array] The `[key, type, offset]` tuples describing the data layout.
			def update_schema(key, schema)
				if allocation = @allocations[key]
					allocation[:schema] = schema
				end
			end
			
			# Read utilization data from an allocated segment.
			#
			# @parameter key [Object] The key used to identify the allocation.
			# @returns [Hash | Nil] The utilization values, or `nil` if the key is not allocated.
			def read(key)
				allocation = @allocations[key]
				return nil unless allocation
				
				offset = allocation[:offset]
				schema = allocation[:schema]
				
				result = {}
				schema.each do |field_key, type, field_offset|
					absolute_offset = offset + field_offset
					
					begin
						result[field_key] = @buffer.get_value(type, absolute_offset)
					rescue => error
						Console.warn(self, "Failed to read value", type: type, key: field_key, offset: absolute_offset, exception: error)
					end
				end
				
				return result
			end
			
			# Resize the shared memory file.
			#
			# The new size is rounded up to the nearest page boundary.
			#
			# @parameter new_size [Integer] The requested new size of the shared memory file.
			# @returns [Boolean] Whether the file was resized successfully.
			def resize(new_size)
				old_size = @size
				return false if new_size <= old_size
				
				page_size = IO::Buffer::PAGE_SIZE
				new_size = (((new_size + page_size - 1) / page_size) * page_size).to_i
				
				begin
					@file.truncate(new_size)
					buffer = IO::Buffer.map(@file, new_size)
					
					@buffer&.free
					@buffer = buffer
					
					old_segment_count = old_size / @segment_size
					new_segment_count = new_size / @segment_size
					
					(old_segment_count...new_segment_count).each do |segment_index|
						@free_list << (segment_index * @segment_size)
					end
					
					@size = new_size
					
					Console.info(self, "Resized shared memory", old_size: old_size, new_size: new_size, segments_added: new_segment_count - old_segment_count)
					
					return true
				rescue => error
					Console.error(self, "Failed to resize shared memory", old_size: old_size, new_size: new_size, exception: error)
					return false
				end
			end
			
			# Close the shared memory file.
			def close
				@buffer&.free
				@buffer = nil
				
				@file&.close
				@file = nil
			end
		end
	end
end
