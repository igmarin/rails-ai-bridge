# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ContextProviderDefinition do
  describe '.from_json' do
    context 'with all fields present' do
      subject(:definition) do
        described_class.from_json({
                                    'type' => 'mcp',
                                    'endpoint' => 'http://localhost:3000/mcp',
                                    'optional' => true,
                                    'tools' => [
                                      'rails_get_schema',
                                      { 'name' => 'rails_get_model_details', 'field' => 'models' }
                                    ]
                                  })
      end

      it 'parses type and endpoint' do
        expect(definition.type).to eq('mcp')
        expect(definition.endpoint).to eq('http://localhost:3000/mcp')
      end

      it 'parses the optional flag' do
        expect(definition.optional).to be(true)
        expect(definition).to be_optional
      end

      it 'parses tools into ContextToolSpec instances' do
        expect(definition.tools.length).to eq(2)
        expect(definition.tools).to all(be_a(RailsAiBridge::Registry::ContextToolSpec))
        expect(definition.tools.first).to be_simple
        expect(definition.tools.last).to be_mapped
      end
    end

    context 'with optional fields omitted' do
      subject(:definition) do
        described_class.from_json({ 'type' => 'mcp', 'endpoint' => 'http://example.test/mcp' })
      end

      it 'defaults optional to false' do
        expect(definition.optional).to be(false)
        expect(definition).not_to be_optional
      end

      it 'defaults tools to an empty array' do
        expect(definition.tools).to eq([])
      end
    end

    context 'when a required field is missing' do
      it 'raises ArgumentError for a missing type' do
        expect { described_class.from_json({ 'endpoint' => 'http://example.test/mcp' }) }
          .to raise_error(ArgumentError, /missing required field: type/)
      end

      it 'raises ArgumentError for a missing endpoint' do
        expect { described_class.from_json({ 'type' => 'mcp' }) }
          .to raise_error(ArgumentError, /missing required field: endpoint/)
      end
    end
  end
end
