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

  describe '.excluded_class_or_table?' do
    let(:config) { RailsAiBridge.configuration }

    around do |example|
      original_models = config.excluded_models.dup
      original_tables = config.excluded_tables.dup
      example.run
    ensure
      config.excluded_models = original_models
      config.excluded_tables = original_tables
    end

    it 'is true when only the table is excluded' do
      config.excluded_tables += %w[patient_records]
      expect(described_class.excluded_class_or_table?('PatientRecord', config)).to be true
    end

    it 'is true for rubydex-decorated class names of an excluded table' do
      config.excluded_tables += %w[patient_records]
      expect(described_class.excluded_class_or_table?('PatientRecord::<PatientRecord>', config)).to be true
    end

    it 'is false when neither the class nor its table is excluded' do
      expect(described_class.excluded_class_or_table?('Post', config)).to be false
    end

    it 'is true for plural and controller tokens when only the model is excluded' do
      config.excluded_models += %w[User]

      expect(described_class.excluded_class_or_table?('User', config)).to be true
      expect(described_class.excluded_class_or_table?('Users', config)).to be true
      expect(described_class.excluded_class_or_table?('users', config)).to be true
      expect(described_class.excluded_class_or_table?('UsersController', config)).to be true
    end

    it 'does not treat a different class as excluded when only User is listed' do
      config.excluded_models += %w[User]

      expect(described_class.excluded_class_or_table?('UserSession', config)).to be false
      expect(described_class.excluded_class_or_table?('Superuser', config)).to be false
    end
  end
end
