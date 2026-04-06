# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/services/configuration_service"

RSpec.describe RailsAiBridge::Services::ConfigurationService do
  describe ".call" do
    it "returns current configuration" do
      result = RailsAiBridge::Services::ConfigurationService.call

      expect(result.success?).to be(true)
      expect(result.data).to be_a(RailsAiBridge::Configuration)
    end

    it "allows configuration updates via block" do
      original_cache_ttl = RailsAiBridge.configuration.introspection.cache_ttl

      begin
        result = RailsAiBridge::Services::ConfigurationService.call do |config|
          config.introspection.cache_ttl = 3600
        end

        expect(result.success?).to be(true)
        expect(result.data.introspection.cache_ttl).to eq(3600)
      ensure
        RailsAiBridge.configuration.introspection.cache_ttl = original_cache_ttl
      end
    end

    it "handles configuration errors" do
      allow(RailsAiBridge).to receive(:configuration).and_raise("Config error")

      result = RailsAiBridge::Services::ConfigurationService.call

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Config error" ])
    end
  end

  describe "#call" do
    subject { RailsAiBridge::Services::ConfigurationService.new }

    it "returns configuration without block" do
      result = subject.call

      expect(result.success?).to be(true)
      expect(result.data).to be_a(RailsAiBridge::Configuration)
    end

    it "yields configuration for modification" do
      original_output_dir = RailsAiBridge.configuration.output_dir

      begin
        result = subject.call do |config|
          config.output_dir = "/tmp/test"
        end

        expect(result.success?).to be(true)
        expect(result.data.output_dir).to eq("/tmp/test")
      ensure
        RailsAiBridge.configuration.output_dir = original_output_dir
      end
    end

    it "handles block errors gracefully" do
      result = subject.call do |config|
        raise "Block error"
      end

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Block error" ])
    end
  end

  describe "configuration access" do
    it "provides access to all configuration sections" do
      result = RailsAiBridge::Services::ConfigurationService.call
      config = result.data

      expect(config).to respond_to(:introspection)
      expect(config).to respond_to(:output)
      expect(config).to respond_to(:mcp)
      expect(config).to respond_to(:server)
      expect(config).to respond_to(:auth)
    end

    it "allows reading configuration values" do
      result = RailsAiBridge::Services::ConfigurationService.call
      config = result.data

      # Test reading some default values
      expect(config.introspection).to be_a(RailsAiBridge::Config::Introspection)
      expect(config.output).to be_a(RailsAiBridge::Config::Output)
      expect(config.introspection.cache_ttl).to be_a(Numeric).or be_nil
    end
  end

  describe "error handling" do
    it "captures StandardError during configuration" do
      allow(RailsAiBridge).to receive(:configuration).and_raise("Config error")

      result = RailsAiBridge::Services::ConfigurationService.call

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Config error" ])
    end

    it "handles block errors gracefully" do
      result = RailsAiBridge::Services::ConfigurationService.call do |config|
        raise "Block error"
      end

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Block error" ])
    end
  end

  describe "result format" do
    it "returns Service::Result with configuration" do
      result = RailsAiBridge::Services::ConfigurationService.call

      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data).to be_a(RailsAiBridge::Configuration)
      expect(result.errors).to be_empty
    end
  end
end
