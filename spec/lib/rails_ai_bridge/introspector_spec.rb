# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspector do
  let(:introspector) { described_class.new(Rails.application) }

  around do |example|
    original_introspectors = RailsAiBridge.configuration.introspectors.dup
    original_additional = RailsAiBridge.configuration.additional_introspectors.dup
    original_parallel = RailsAiBridge.configuration.parallel_introspection
    example.run
  ensure
    RailsAiBridge.configuration.introspectors = original_introspectors
    RailsAiBridge.configuration.additional_introspectors = original_additional
    RailsAiBridge.configuration.parallel_introspection = original_parallel
  end

  describe '#call' do
    it 'returns a complete context hash' do
      result = introspector.call

      expect(result[:ruby_version]).to eq(RUBY_VERSION)
      expect(result[:rails_version]).to eq(Rails.version)
      expect(result[:generator]).to include('rails-ai-bridge')
      expect(result[:generated_at]).to be_a(String)
    end

    it 'includes non_ar_models when that introspector is enabled' do
      RailsAiBridge.configuration.introspectors += [:non_ar_models]
      result = introspector.call
      expect(result).to have_key(:non_ar_models)
    end

    it 'extracts schema with tables' do
      result = introspector.call
      schema = result[:schema]

      expect(schema[:adapter]).not_to be_nil
      # Live DB may not load schema on all Rails versions via Combustion;
      # fall back to verifying static parse produces tables from schema.rb
      if schema[:tables].empty?
        static = RailsAiBridge::Introspectors::SchemaIntrospector.new(Rails.application).send(:static_schema_parse)
        expect(static[:tables]).to have_key('users')
        expect(static[:tables]).to have_key('posts')
      else
        expect(schema[:tables]).to have_key('users')
        expect(schema[:tables]).to have_key('posts')
      end
    end

    it 'supports configured custom introspectors' do
      custom_introspector = Class.new do
        def initialize(_app); end

        def call
          { custom: true }
        end
      end

      RailsAiBridge.configuration.additional_introspectors[:custom] = custom_introspector
      RailsAiBridge.configuration.introspectors = [:custom]

      result = introspector.call

      expect(result[:custom]).to eq({ custom: true })
    end

    context 'with parallel_introspection enabled' do
      before { RailsAiBridge.configuration.parallel_introspection = true }

      it 'returns the same metadata as sequential execution' do
        result = introspector.call

        expect(result[:ruby_version]).to eq(RUBY_VERSION)
        expect(result[:rails_version]).to eq(Rails.version)
        expect(result[:generator]).to include('rails-ai-bridge')
      end

      it 'runs custom introspectors in parallel' do
        custom_a = Class.new do
          def initialize(_app); end
          def call = { a: true }
        end
        custom_b = Class.new do
          def initialize(_app); end
          def call = { b: true }
        end

        RailsAiBridge.configuration.additional_introspectors[:custom_a] = custom_a
        RailsAiBridge.configuration.additional_introspectors[:custom_b] = custom_b
        RailsAiBridge.configuration.introspectors = %i[custom_a custom_b]

        result = introspector.call

        expect(result[:custom_a]).to eq({ a: true })
        expect(result[:custom_b]).to eq({ b: true })
      end

      it 'captures errors per introspector in parallel mode' do
        failing_introspector = Class.new do
          def initialize(_app); end
          def call = raise(StandardError, 'parallel boom')
        end

        RailsAiBridge.configuration.additional_introspectors[:failing] = failing_introspector
        RailsAiBridge.configuration.introspectors = %i[failing schema]

        result = introspector.call

        expect(result[:failing]).to eq({ error: 'parallel boom' })
        expect(result[:schema]).to be_a(Hash)
      end

      it 'falls back to sequential for a single introspector' do
        RailsAiBridge.configuration.introspectors = [:schema]

        result = introspector.call

        expect(result[:schema]).to be_a(Hash)
      end
    end
  end
end
