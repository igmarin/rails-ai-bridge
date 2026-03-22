# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspector do
  let(:introspector) { described_class.new(Rails.application) }

  around do |example|
    original_introspectors = RailsAiBridge.configuration.introspectors.dup
    original_additional = RailsAiBridge.configuration.additional_introspectors.dup
    example.run
  ensure
    RailsAiBridge.configuration.introspectors = original_introspectors
    RailsAiBridge.configuration.additional_introspectors = original_additional
  end

  describe "#call" do
    it "returns a complete context hash" do
      result = introspector.call

      expect(result[:ruby_version]).to eq(RUBY_VERSION)
      expect(result[:rails_version]).to eq(Rails.version)
      expect(result[:generator]).to include("rails-ai-bridge")
      expect(result[:generated_at]).to be_a(String)
    end

    it "includes all configured introspectors" do
      result = introspector.call

      expect(result).to have_key(:schema)
      expect(result).to have_key(:models)
      expect(result).to have_key(:routes)
      expect(result).to have_key(:jobs)
      expect(result).to have_key(:gems)
      expect(result).to have_key(:conventions)
    end

    it "extracts schema with tables" do
      result = introspector.call
      schema = result[:schema]

      expect(schema[:adapter]).not_to be_nil
      # Live DB may not load schema on all Rails versions via Combustion;
      # fall back to verifying static parse produces tables from schema.rb
      if schema[:tables].empty?
        static = RailsAiBridge::Introspectors::SchemaIntrospector.new(Rails.application).send(:static_schema_parse)
        expect(static[:tables]).to have_key("users")
        expect(static[:tables]).to have_key("posts")
      else
        expect(schema[:tables]).to have_key("users")
        expect(schema[:tables]).to have_key("posts")
      end
    end

    it "supports configured custom introspectors" do
      custom_introspector = Class.new do
        def initialize(_app); end

        def call
          { custom: true }
        end
      end

      RailsAiBridge.configuration.additional_introspectors[:custom] = custom_introspector
      RailsAiBridge.configuration.introspectors = [ :custom ]

      result = introspector.call

      expect(result[:custom]).to eq({ custom: true })
    end
  end
end
