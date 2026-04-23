# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/service_errors'

RSpec.describe RailsAiBridge::ServiceErrors do
  describe 'error hierarchy' do
    it 'has BaseError as parent class' do
      expect(described_class::BaseError).to be < StandardError
    end

    it 'has specific error classes' do
      expect(described_class::ValidationError).to be < described_class::BaseError
      expect(described_class::NotFoundError).to be < described_class::BaseError
      expect(described_class::AuthorizationError).to be < described_class::BaseError
      expect(described_class::SerializationError).to be < described_class::BaseError
      # ConfigurationError and IntrospectionError inherit from top-level errors
      expect(described_class::ConfigurationError).to be < RailsAiBridge::ConfigurationError
      expect(described_class::IntrospectionError).to be < RailsAiBridge::IntrospectionError
    end
  end

  describe 'error instantiation' do
    it 'can create validation error' do
      error = described_class::ValidationError.new('Invalid input')
      expect(error.message).to eq('Invalid input')
    end

    it 'can create not found error' do
      error = described_class::NotFoundError.new('Resource not found')
      expect(error.message).to eq('Resource not found')
    end

    it 'can create authorization error' do
      error = described_class::AuthorizationError.new('Access denied')
      expect(error.message).to eq('Access denied')
    end

    it 'can create configuration error' do
      error = described_class::ConfigurationError.new('Invalid config')
      expect(error.message).to eq('Invalid config')
      expect(error).to be_a(RailsAiBridge::ConfigurationError)
    end

    it 'can create introspection error' do
      error = described_class::IntrospectionError.new('Introspection failed')
      expect(error.message).to eq('Introspection failed')
      expect(error).to be_a(RailsAiBridge::IntrospectionError)
    end

    it 'can create serialization error' do
      error = described_class::SerializationError.new('Serialization failed')
      expect(error.message).to eq('Serialization failed')
    end
  end

  describe 'error usage in services' do
    it 'can be used in service result' do
      error = described_class::ConfigurationError.new('Invalid config')
      result = RailsAiBridge::Service::Result.new(false, errors: [error.message])

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([error.message])
    end

    it 'maintains error taxonomy consistency' do
      # Service errors that inherit from top-level errors should be catchable by both
      service_error = described_class::ConfigurationError.new('Config error')

      expect(service_error).to be_a(described_class::ConfigurationError)
      expect(service_error).to be_a(RailsAiBridge::ConfigurationError)
      expect(service_error).to be_a(StandardError)
    end
  end
end
