# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/schema_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::SchemaFormatter do
  describe '#call' do
    it 'returns nil when the schema key is absent' do
      expect(described_class.new({}).call).to be_nil
    end

    it 'returns nil when schema has an :error key' do
      expect(described_class.new({ schema: { error: 'failed' } }).call).to be_nil
    end

    it 'renders the heading with the table count when tables are absent' do
      result = described_class.new({ schema: { total_tables: 5 } }).call

      expect(result).to eq('## Database Schema (5 tables)')
    end

    it 'renders tables with their columns' do
      ctx = {
        schema: {
          total_tables: 1,
          tables: {
            'users' => { columns: [{ name: 'id', type: 'integer' }, { name: 'email', type: 'string' }] }
          }
        }
      }

      result = described_class.new(ctx).call

      expect(result).to include('### users')
      expect(result).to include('`id` (integer)')
      expect(result).to include('`email` (string)')
    end

    it 'renders a table with no columns as an empty line' do
      ctx = { schema: { total_tables: 1, tables: { 'users' => {} } } }

      result = described_class.new(ctx).call

      expect(result).to include('### users')
    end
  end
end
