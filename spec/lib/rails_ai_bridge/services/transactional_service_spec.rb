# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/services/transactional_service"

RSpec.describe RailsAiBridge::Services::TransactionalService do
  describe ".call" do
    it "executes transaction and returns result" do
      result = described_class.call do
        Service::Result.new(true, data: "success")
      end
      
      expect(result.success?).to be(true)
      expect(result.data).to eq("success")
    end

    it "handles exceptions gracefully" do
      result = described_class.call do
        raise StandardError, "Test error"
      end
      
      expect(result.failure?).to be(true)
      expect(result.errors).to eq(["Test error"])
    end

    it "requires a block" do
      expect {
        described_class.call
      }.to raise_error(ArgumentError, "Block is required")
    end

    it "validates block return type" do
      result = described_class.call do
        "not a Service::Result"
      end
      
      expect(result.failure?).to be(true)
      expect(result.errors).to eq(["Block must return Service::Result"])
    end
  end

  describe "#call" do
    subject { described_class.new }

    it "provides transaction context" do
      result = subject.call do
        Service::Result.new(true, data: {transaction: "active"})
      end
      
      expect(result.success?).to be(true)
      expect(result.data[:transaction]).to eq("active")
    end

    it "supports nested transactions" do
      result = subject.call do
        inner_result = described_class.call do
          Service::Result.new(true, data: "nested")
        end
        
        expect(inner_result.success?).to be(true)
        expect(inner_result.data).to eq("nested")
        
        Service::Result.new(true, data: "outer")
      end
      
      expect(result.success?).to be(true)
      expect(result.data).to eq("outer")
    end
  end

  describe "transaction management" do
    it "ensures consistent error handling" do
      result = described_class.call do
        # Simulate operation
        Service::Result.new(true, data: "done")
      end
      
      expect(result.success?).to be(true)
      expect(result.data).to eq("done")
    end
  end

  describe "result format" do
    it "returns Service::Result for all outcomes" do
      # Success
      success_result = described_class.call { Service::Result.new(true, data: "ok") }
      expect(success_result).to be_a(RailsAiBridge::Service::Result)
      expect(success_result.success?).to be(true)
      
      # Failure
      failure_result = described_class.call { raise "error" }
      expect(failure_result).to be_a(RailsAiBridge::Service::Result)
      expect(failure_result.failure?).to be(true)
    end
  end
end
