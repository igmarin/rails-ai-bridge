# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ExclusionHelper do
  describe '.table_pattern_match?' do
    # Method signature: (pattern, table_name)

    it 'matches exact table name' do
      expect(described_class.table_pattern_match?('users', 'users')).to be true
    end

    it 'rejects non-matching exact name' do
      expect(described_class.table_pattern_match?('posts', 'users')).to be false
    end

    it 'matches trailing wildcard pattern' do
      expect(described_class.table_pattern_match?('pii_*', 'pii_addresses')).to be true
    end

    it 'matches leading wildcard pattern' do
      expect(described_class.table_pattern_match?('*_archive', 'old_users_archive')).to be true
    end

    it 'matches middle wildcard pattern' do
      expect(described_class.table_pattern_match?('*data*', 'temp_data_backup')).to be true
    end

    it 'is case-sensitive' do
      expect(described_class.table_pattern_match?('users', 'Users')).to be false
    end

    it 'returns false for empty pattern' do
      expect(described_class.table_pattern_match?('', 'users')).to be false
    end

    it 'returns false for nil pattern' do
      expect(described_class.table_pattern_match?(nil, 'users')).to be false
    end

    it 'returns false for empty table name' do
      expect(described_class.table_pattern_match?('users', '')).to be false
    end

    it 'returns false for nil table name' do
      expect(described_class.table_pattern_match?('users', nil)).to be false
    end

    it 'supports extglob brace patterns' do
      expect(described_class.table_pattern_match?('{audit,pii}_*', 'audit_logs')).to be true
      expect(described_class.table_pattern_match?('{audit,pii}_*', 'pii_records')).to be true
      expect(described_class.table_pattern_match?('{audit,pii}_*', 'user_logs')).to be false
    end
  end
end
