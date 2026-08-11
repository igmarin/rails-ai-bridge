# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ContextToolSpec do
  describe '.from_json' do
    context 'with a plain tool name string' do
      subject(:spec) { described_class.from_json('rails_get_schema') }

      it 'builds a simple spec with the tool name' do
        expect(spec.name).to eq('rails_get_schema')
      end

      it 'leaves field and arguments nil' do
        expect(spec.field).to be_nil
        expect(spec.arguments).to be_nil
      end

      it 'is simple and not mapped' do
        expect(spec).to be_simple
        expect(spec).not_to be_mapped
      end
    end

    context 'with a mapped tool hash' do
      subject(:spec) do
        described_class.from_json({
                                    'name' => 'rails_get_model_details',
                                    'field' => 'models',
                                    'arguments' => { 'model' => 'User' }
                                  })
      end

      it 'builds a mapped spec with name, field, and arguments' do
        expect(spec.name).to eq('rails_get_model_details')
        expect(spec.field).to eq('models')
        expect(spec.arguments).to eq({ 'model' => 'User' })
      end

      it 'is mapped and not simple' do
        expect(spec).to be_mapped
        expect(spec).not_to be_simple
      end
    end

    context 'with a mapped tool hash without arguments' do
      it 'defaults arguments to nil' do
        spec = described_class.from_json({ 'name' => 'rails_get_schema', 'field' => 'schema' })
        expect(spec.arguments).to be_nil
      end
    end

    context 'when a mapped tool is missing a required field' do
      it 'raises ArgumentError naming the missing field' do
        expect { described_class.from_json({ 'name' => 'rails_get_schema' }) }
          .to raise_error(ArgumentError, /missing required field: field/)
      end
    end

    context 'with an unsupported value type' do
      it 'raises ArgumentError' do
        expect { described_class.from_json(42) }
          .to raise_error(ArgumentError, /must be a String or an object/)
      end
    end
  end
end
