# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/migrations_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::MigrationsFormatter do
  describe '#call' do
    it 'returns nil when the migrations key is absent' do
      expect(described_class.new({}).call).to be_nil
    end

    it 'returns nil when migrations has an :error key' do
      expect(described_class.new({ migrations: { error: 'failed' } }).call).to be_nil
    end

    it 'renders the Migrations heading with total count' do
      result = described_class.new({ migrations: { total: 12 } }).call
      expect(result).to include('## Migrations')
      expect(result).to include('- Total: 12')
    end

    it 'renders schema_version when present' do
      result = described_class.new({ migrations: { total: 5, schema_version: '20240101000000' } }).call
      expect(result).to include('- Schema version: 20240101000000')
    end

    it 'omits schema_version when absent' do
      result = described_class.new({ migrations: { total: 5 } }).call
      expect(result).not_to include('Schema version')
    end

    it 'omits Pending Migrations section when pending is empty' do
      result = described_class.new({ migrations: { total: 3, pending: [] } }).call
      expect(result).not_to include('Pending Migrations')
    end

    it 'renders Pending Migrations when present' do
      pending = [
        { version: '20240201000001', name: 'AddNameToUsers' }
      ]
      result = described_class.new({ migrations: { total: 1, pending: pending } }).call
      expect(result).to include('### Pending Migrations (1)')
      expect(result).to include('`20240201000001` AddNameToUsers')
    end

    it 'renders multiple pending migrations' do
      pending = [
        { version: '20240201000001', name: 'AddNameToUsers' },
        { version: '20240201000002', name: 'CreatePosts' }
      ]
      result = described_class.new({ migrations: { total: 2, pending: pending } }).call
      expect(result).to include('### Pending Migrations (2)')
      expect(result).to include('`20240201000001` AddNameToUsers')
      expect(result).to include('`20240201000002` CreatePosts')
    end

    it 'omits Recent Migrations section when recent is empty' do
      result = described_class.new({ migrations: { total: 3, recent: [] } }).call
      expect(result).not_to include('Recent Migrations')
    end

    it 'renders Recent Migrations without actions when actions are absent' do
      recent = [{ version: '20240101000000', name: 'CreateUsers', actions: [] }]
      result = described_class.new({ migrations: { total: 1, recent: recent } }).call
      expect(result).to include('### Recent Migrations')
      expect(result).to include('`20240101000000` CreateUsers')
      expect(result).not_to match(/CreateUsers \(/)
    end

    it 'renders Recent Migrations with actions when present' do
      recent = [{ version: '20240101000001', name: 'AddIndexToEmail', actions: %w[add_index add_column] }]
      result = described_class.new({ migrations: { total: 1, recent: recent } }).call
      expect(result).to include('`20240101000001` AddIndexToEmail (add_index, add_column)')
    end

    it 'renders all sections together' do
      data = {
        total: 10,
        schema_version: '20240201000002',
        pending: [{ version: '20240201000001', name: 'AddSomething' }],
        recent: [{ version: '20240101000000', name: 'CreateUsers', actions: ['create_table'] }]
      }
      result = described_class.new({ migrations: data }).call
      expect(result).to include('## Migrations')
      expect(result).to include('- Total: 10')
      expect(result).to include('Schema version: 20240201000002')
      expect(result).to include('Pending Migrations')
      expect(result).to include('AddSomething')
      expect(result).to include('Recent Migrations')
      expect(result).to include('CreateUsers')
    end
  end
end
