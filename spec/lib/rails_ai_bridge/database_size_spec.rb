# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::DatabaseSize do
  describe '.bucket' do
    it 'returns nil for a nil row count' do
      expect(described_class.bucket(nil)).to be_nil
    end

    it 'maps exact bucket boundaries to the correct label' do
      expect(described_class.bucket(0)).to eq('small')
      expect(described_class.bucket(49_999)).to eq('small')
      expect(described_class.bucket(50_000)).to eq('medium')
      expect(described_class.bucket(999_999)).to eq('medium')
      expect(described_class.bucket(1_000_000)).to eq('large')
      expect(described_class.bucket(9_999_999)).to eq('large')
      expect(described_class.bucket(10_000_000)).to eq('hot')
    end

    it 'maps counts above ten million to hot' do
      expect(described_class.bucket(25_000_000)).to eq('hot')
    end

    it 'returns nil for negative counts (invalid statistics sentinels)' do
      expect(described_class.bucket(-1)).to be_nil
      expect(described_class.bucket(-10_000_000)).to be_nil
    end

    it 'passes precomputed safe labels through unchanged' do
      expect(described_class.bucket('small')).to eq('small')
      expect(described_class.bucket('medium')).to eq('medium')
      expect(described_class.bucket('large')).to eq('large')
      expect(described_class.bucket('hot')).to eq('hot')
    end

    it 'parses numeric strings' do
      expect(described_class.bucket('75000')).to eq('medium')
    end

    it 'returns nil for non-numeric strings' do
      expect(described_class.bucket('gigantic')).to be_nil
    end
  end

  describe '#bucket' do
    it 'delegates to .bucket' do
      expect(described_class.new({}).bucket(50_000)).to eq('medium')
    end
  end

  describe '.bucket_for_table' do
    it 'returns the precomputed size bucket when present' do
      context = {
        database_stats: {
          tables: [
            { table: 'users', approximate_rows: 12, size_bucket: 'hot' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'users')).to eq('hot')
    end

    it 'returns nil for an invalid precomputed size bucket label' do
      context = {
        database_stats: {
          tables: [
            { table: 'users', approximate_rows: 12, size_bucket: 'gigantic' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'users')).to be_nil
    end

    it 'buckets numeric string approximate_rows' do
      context = {
        database_stats: {
          tables: [
            { table: 'events', approximate_rows: '75000' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'events')).to eq('medium')
    end

    it 'matches string-keyed table rows' do
      context = {
        database_stats: {
          tables: [
            { 'table' => 'posts', 'approximate_rows' => 25_000_000, 'size_bucket' => 'small' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'posts')).to eq('small')
    end

    it 'buckets approximate_rows when no size bucket is precomputed' do
      context = {
        database_stats: {
          tables: [
            { table: 'events', approximate_rows: 50_000 }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'events')).to eq('medium')
    end

    it 'returns nil when the found row carries no count data' do
      context = { database_stats: { tables: [{ table: 'events' }] } }

      expect(described_class.bucket_for_table(context, 'events')).to be_nil
    end

    it 'returns nil for a missing table' do
      context = {
        database_stats: {
          tables: [
            { table: 'users', approximate_rows: 10, size_bucket: 'small' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, 'comments')).to be_nil
    end

    it 'returns nil for nil and empty table names' do
      context = {
        database_stats: {
          tables: [
            { table: 'users', approximate_rows: 10, size_bucket: 'small' }
          ]
        }
      }

      expect(described_class.bucket_for_table(context, nil)).to be_nil
      expect(described_class.bucket_for_table(context, '')).to be_nil
    end

    it 'returns nil when stats errored or were skipped' do
      errored = { database_stats: { error: 'connection refused' } }
      skipped = { database_stats: { skipped: true, reason: 'Only available for PostgreSQL' } }

      expect(described_class.bucket_for_table(errored, 'users')).to be_nil
      expect(described_class.bucket_for_table(skipped, 'users')).to be_nil
    end

    it 'returns nil when context has no database stats' do
      expect(described_class.bucket_for_table({}, 'users')).to be_nil
      expect(described_class.bucket_for_table(nil, 'users')).to be_nil
    end

    it 'returns nil when stats are not a Hash' do
      expect(described_class.bucket_for_table({ database_stats: 'unavailable' }, 'users')).to be_nil
    end

    it 'returns nil when tables are empty or missing' do
      expect(described_class.bucket_for_table({ database_stats: { tables: [] } }, 'users')).to be_nil
      expect(described_class.bucket_for_table({ database_stats: {} }, 'users')).to be_nil
    end
  end

  describe '#bucket_for_table' do
    it 'resolves the bucket for a table from the given context' do
      context = { database_stats: { tables: [{ table: 'users', approximate_rows: 1_000_000 }] } }

      expect(described_class.new(context).bucket_for_table('users')).to eq('large')
    end
  end
end
