# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::ServiceErrors do
  describe "error hierarchy" do
    it "has BaseError as parent class" do
      expect(described_class::BaseError).to be < StandardError
    end

    it "has specific error classes" do
      expect(described_class::ValidationError).to be < described_class::BaseError
      expect(described_class::NotFoundError).to be < described_class::BaseError
      expect(described_class::AuthorizationError).to be < described_class::BaseError
      expect(described_class::ConfigurationError).to be < described_class::BaseError
      expect(described_class::IntrospectionError).to be < described_class::BaseError
      expect(described_class::SerializationError).to be < described_class::BaseError
    end
  end

  describe "error instantiation" do
    it "can create validation error" do
      error = described_class::ValidationError.new("Invalid input")
      expect(error.message).to eq("Invalid input")
    end

    it "can create not found error" do
      error = described_class::NotFoundError.new("Resource not found")
      expect(error.message).to eq("Resource not found")
    end

    it "can create authorization error" do
      error = described_class::AuthorizationError.new("Access denied")
      expect(error.message).to eq("Access denied")
    end
  end

  describe "error usage in services" do
    it "can be used in service result" do
      error = described_class::ConfigurationError.new("Invalid config")
      result = RailsAiBridge::Service::Result.new(false, errors: [error.message])
      
      expect(result.failure?).to be(true)
      expect(result.errors).to eq([error.message])
    end
  end
end
