# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "async/utilization"

describe Async::Utilization::Registry do
	let(:registry) {Async::Utilization::Registry.new}
	
	it "can increment a value" do
		value = registry.increment(:test_field)
		expect(value).to be == 1
		expect(registry.values[:test_field]).to be == 1
	end
	
	it "can increment multiple times" do
		registry.increment(:test_field)
		registry.increment(:test_field)
		registry.increment(:test_field)
		
		expect(registry.values[:test_field]).to be == 3
	end
	
	it "can decrement a value" do
		registry.increment(:test_field)
		registry.increment(:test_field)
		
		value = registry.decrement(:test_field)
		expect(value).to be == 1
		expect(registry.values[:test_field]).to be == 1
	end
	
	it "can set a value directly" do
		registry.set(:test_field, 42)
		expect(registry.values[:test_field]).to be == 42
	end
	
	it "can track an operation with auto-decrement" do
		registry.track(:test_field) do
			expect(registry.values[:test_field]).to be == 1
		end
		
		expect(registry.values[:test_field]).to be == 0
	end
	
	it "decrements even if track block raises an error" do
		begin
			registry.track(:test_field) do
				raise "Error!"
			end
		rescue
		end
		
		expect(registry.values[:test_field]).to be == 0
	end
	
	it "notifies observer when values change" do
		schema = Async::Utilization::Schema.build(test_field: :u64)
		buffer = IO::Buffer.new(8)

		observer = Object.new
		observer.define_singleton_method(:schema) { schema }
		observer.define_singleton_method(:buffer) { buffer }

		registry.set(:test_field, 5)
		registry.observer = observer

		# Buffer should be synced with the existing value on observer assignment
		expect(buffer.get_value(:u64, 0)).to be == 5

		registry.increment(:test_field)

		# Buffer should reflect the incremented value
		expect(buffer.get_value(:u64, 0)).to be == 6
	end
	
	it "uses metric method for fast path" do
		registry.metric(:module_test).increment
		registry.metric(:module_test).increment
		
		expect(registry.values).to have_keys(module_test: be == 2)
	end
	
	it "can use metric for decrement" do
		registry.metric(:module_decrement_test).increment
		registry.metric(:module_decrement_test).increment
		registry.metric(:module_decrement_test).decrement
		
		expect(registry.values).to have_keys(module_decrement_test: be == 1)
	end
	
	it "can use metric for set" do
		registry.metric(:module_set_test).set(99)
		
		expect(registry.values).to have_keys(module_set_test: be == 99)
	end
	
	it "can set observer" do
		observer = Object.new
		def observer.set(field, value); end
		
		registry.observer = observer
		
		expect(registry.observer).to be == observer
	end
end
