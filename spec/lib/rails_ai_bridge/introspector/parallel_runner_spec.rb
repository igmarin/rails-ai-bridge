# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspector::ParallelRunner do
  let(:app) { Rails.application }

  describe '.call' do
    let(:schema_class) { class_double(RailsAiBridge::Introspectors::SchemaIntrospector) }
    let(:model_class) { class_double(RailsAiBridge::Introspectors::ModelIntrospector) }

    it 'runs introspectors and returns results keyed by name' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      model_instance = double('ModelIntrospector', call: { 'User' => {} })

      introspectors = {
        schema: schema_class,
        models: model_class
      }

      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)
      allow(model_class).to receive(:new).with(app).and_return(model_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
      expect(result[:models]).to eq({ 'User' => {} })
    end

    it 'captures errors per introspector without raising' do
      schema_instance = double('SchemaIntrospector')
      allow(schema_instance).to receive(:call).and_raise(StandardError, 'schema boom')

      introspectors = { schema: schema_class }
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ error: 'schema boom' })
    end

    it 'handles mixed success and failure' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      model_instance = double('ModelIntrospector')
      allow(model_instance).to receive(:call).and_raise(StandardError, 'model fail')

      introspectors = {
        schema: schema_class,
        models: model_class
      }

      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)
      allow(model_class).to receive(:new).with(app).and_return(model_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
      expect(result[:models]).to eq({ error: 'model fail' })
    end

    it 'returns empty hash for empty introspector list' do
      result = described_class.call({}, app)
      expect(result).to eq({})
    end

    it 'works with single introspector' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      introspectors = { schema: schema_class }
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
    end
  end

  describe '.available?' do
    it 'returns true when concurrent-ruby is installed' do
      expect(described_class.available?).to be true
    end
  end
end
