# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus"
require "async/utilization"

describe Async::Utilization::Interface do
	let(:interface) {Async::Utilization::Interface.new}
	
	it "can increment a value" do
		value = interface.increment(:test_field)
		expect(value).to be == 1
		expect(interface.values[:test_field]).to be == 1
	end
	
	it "can increment multiple times" do
		interface.increment(:test_field)
		interface.increment(:test_field)
		interface.increment(:test_field)
		
		expect(interface.values[:test_field]).to be == 3
	end
	
	it "can decrement a value" do
		interface.increment(:test_field)
		interface.increment(:test_field)
		
		value = interface.decrement(:test_field)
		expect(value).to be == 1
		expect(interface.values[:test_field]).to be == 1
	end
	
	it "can set a value directly" do
		interface.set(:test_field, 42)
		expect(interface.values[:test_field]).to be == 42
	end
	
	it "can auto-decrement with a block" do
		interface.increment(:test_field) do
			expect(interface.values[:test_field]).to be == 1
		end
		
		expect(interface.values[:test_field]).to be == 0
	end
	
	it "decrements even if block raises an error" do
		begin
			interface.increment(:test_field) do
				raise "Error!"
			end
		rescue
		end
		
		expect(interface.values[:test_field]).to be == 0
	end
	
	it "can set an observer" do
		observer = Object.new
		def observer.set(field, value); end
		
		interface.set(:test_field, 10)
		interface.observer = observer
		
		expect(interface.observer).to be == observer
	end
	
	it "notifies observer when values change" do
		values_set = []
		
		# Create a proper observer with schema
		schema = Async::Utilization::Schema.build(test_field: :u64)
		observer = Object.new
		
		# Define methods on observer
		observer.define_singleton_method(:set) do |field, value|
			values_set << [field, value]
		end
		observer.define_singleton_method(:schema) { schema }
		observer.define_singleton_method(:buffer) { nil }  # No buffer, so write_direct will return false
		
		interface.set(:test_field, 5)
		interface.observer = observer
		
		# Observer should be notified of existing values
		expect(values_set).to be(:include?, [:test_field, 5])
		
		# Clear and test new changes
		# Note: Since observer has no buffer, write_direct will return false
		# and no notification will occur (as per new design)
		values_set.clear
		interface.increment(:test_field)
		
		# With no buffer, write_direct fails silently, so no notification
		expect(values_set).to be == []
	end
	
	it "uses metric method for fast path" do
		Async::Utilization.metric(:module_test).increment
		Async::Utilization.metric(:module_test).increment
		
		interface = Async::Utilization::Interface.instance
		expect(interface.values).to have_keys(module_test: be == 2)
	end
	
	it "can use metric for decrement" do
		Async::Utilization.metric(:module_decrement_test).increment
		Async::Utilization.metric(:module_decrement_test).increment
		Async::Utilization.metric(:module_decrement_test).decrement
		
		interface = Async::Utilization::Interface.instance
		expect(interface.values).to have_keys(module_decrement_test: be == 1)
	end
	
	it "can use metric for set" do
		Async::Utilization.metric(:module_set_test).set(99)
		
		interface = Async::Utilization::Interface.instance
		expect(interface.values).to have_keys(module_set_test: be == 99)
	end
	
	it "can set observer via module-level method" do
		observer = Object.new
		def observer.set(field, value); end
		
		Async::Utilization.observer = observer
		
		interface = Async::Utilization::Interface.instance
		expect(interface.observer).to be == observer
	end
end
