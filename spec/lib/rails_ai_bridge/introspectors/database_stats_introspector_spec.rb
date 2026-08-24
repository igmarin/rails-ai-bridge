# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::DatabaseStatsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    it 'returns skipped for non-PostgreSQL adapter' do
      result = introspector.call
      # Test suite uses SQLite — should skip
      expect(result[:skipped]).to be(true)
      expect(result[:reason]).to include('PostgreSQL')
    end

    it 'adds size buckets for PostgreSQL approximate row counts' do
      connection = instance_double(
        ActiveRecord::ConnectionAdapters::AbstractAdapter,
        adapter_name: 'PostgreSQL',
        select_all: [
          { 'table_name' => 'events', 'approximate_row_count' => 25_000_000 },
          { 'table_name' => 'users', 'approximate_row_count' => 75_000 }
        ]
      )
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

      result = introspector.call

      expect(result[:tables]).to include(
        { table: 'events', approximate_rows: 25_000_000, size_bucket: 'hot' },
        { table: 'users', approximate_rows: 75_000, size_bucket: 'medium' }
      )
    end

    it 'returns error hash on connection error' do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(StandardError, 'connection failed')

      result = introspector.call
      expect(result[:error]).to eq('connection failed')
    end

    context 'when ActiveRecord is not defined' do
      before { hide_const('ActiveRecord') }

      it 'returns skipped with reason' do
        result = introspector.call
        expect(result[:skipped]).to be(true)
        expect(result[:reason]).to eq('ActiveRecord not available')
      end
    end

    context 'with MySQL adapter' do
      it 'returns skipped with adapter name in reason' do
        connection = instance_double(
          ActiveRecord::ConnectionAdapters::AbstractAdapter,
          adapter_name: 'MySQL'
        )
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

        result = introspector.call
        expect(result[:skipped]).to be(true)
        expect(result[:reason]).to include('mysql')
      end
    end

    context 'with empty PostgreSQL result' do
      it 'returns zero total_tables' do
        connection = instance_double(
          ActiveRecord::ConnectionAdapters::AbstractAdapter,
          adapter_name: 'PostgreSQL',
          select_all: []
        )
        allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

        result = introspector.call
        expect(result[:total_tables]).to eq(0)
        expect(result[:tables]).to eq([])
      end
    end
  end
end
