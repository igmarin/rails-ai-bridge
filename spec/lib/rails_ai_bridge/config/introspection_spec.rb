# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Introspection do
  subject(:introspection) { described_class.new }

  it 'defaults to the standard preset' do
    expect(introspection.introspectors).to eq(RailsAiBridge::Configuration::PRESETS[:standard])
  end

  it 'defaults excluded_paths' do
    expect(introspection.excluded_paths).to include('node_modules', 'tmp', 'vendor')
  end

  it 'defaults excluded_models to Rails internal models' do
    expect(introspection.excluded_models).to include('ApplicationRecord', 'ActiveStorage::Blob')
  end

  it 'defaults core_models to []' do
    expect(introspection.core_models).to eq([])
  end

  it 'defaults excluded_tables to []' do
    expect(introspection.excluded_tables).to eq([])
  end

  it 'defaults disabled_introspection_categories to []' do
    expect(introspection.disabled_introspection_categories).to eq([])
  end

  it 'defaults cache_ttl to 30' do
    expect(introspection.cache_ttl).to eq(30)
  end

  it 'defaults expose_credentials_key_names to false' do
    expect(introspection.expose_credentials_key_names).to be(false)
  end

  it 'defaults additional_introspectors to {}' do
    expect(introspection.additional_introspectors).to eq({})
  end

  it 'defaults search_code_allowed_file_types to []' do
    expect(introspection.search_code_allowed_file_types).to eq([])
  end

  it 'defaults search_code_pattern_max_bytes to 2048' do
    expect(introspection.search_code_pattern_max_bytes).to eq(2048)
  end

  it 'defaults search_code_timeout_seconds to 5.0' do
    expect(introspection.search_code_timeout_seconds).to eq(5.0)
  end

  describe '#preset=' do
    it 'sets introspectors from a named preset' do
      introspection.preset = :full
      expect(introspection.introspectors.size).to eq(27)
    end

    it 'raises on unknown preset' do
      expect { introspection.preset = :unknown }.to raise_error(ArgumentError, /Unknown preset/)
    end
  end

  describe '#effective_introspectors' do
    it 'returns all when no categories disabled' do
      expect(introspection.effective_introspectors).to eq(introspection.introspectors)
    end

    it 'subtracts domain_metadata category' do
      introspection.disabled_introspection_categories << :domain_metadata
      expect(introspection.effective_introspectors).not_to include(:schema, :models, :non_ar_models, :migrations)
    end
  end

  describe '#excluded_table?' do
    it 'returns false when excluded_tables is empty' do
      expect(introspection.excluded_table?('users')).to be false
    end

    it 'matches exact table name' do
      introspection.excluded_tables << 'secrets'
      expect(introspection.excluded_table?('secrets')).to be true
    end

    it 'matches glob pattern' do
      introspection.excluded_tables << 'audit_*'
      expect(introspection.excluded_table?('audit_logs')).to be true
    end
  end

  # --------------------------------------------------------------------------
  # Characterization tests for refactoring targets
  # --------------------------------------------------------------------------

  describe 'initialization behavior' do
    it 'defines initialize method on the class (not inherited)' do
      # Behavioral assertion: initialize should be defined directly on this class
      expect(described_class.instance_method(:initialize).owner)
        .to eq(described_class)
    end
  end

  describe 'preset reader behavior' do
    it 'exposes a preset reader on Introspection' do
      expect(introspection.respond_to?(:preset)).to be(true)
    end

    it 'returns :standard by default' do
      expect(introspection.preset).to eq(:standard)
    end

    it 'returns the preset name after setting it' do
      introspection.preset = :full
      expect(introspection.preset).to eq(:full)
    end

    it 'returns :standard after setting standard preset' do
      introspection.preset = :standard
      expect(introspection.preset).to eq(:standard)
    end

    it 'returns the last preset set when changed' do
      introspection.preset = :standard
      introspection.preset = :full
      expect(introspection.preset).to eq(:full)
    end

    it 'returns nil when introspectors are modified directly (not via preset=)' do
      introspection.preset = :standard
      expect(introspection.preset).to eq(:standard)
      introspection.introspectors += %i[views]
      expect(introspection.preset).to be_nil
    end
  end

  describe 'domain metadata introspector category' do
    it 'non_ar_models is in domain_metadata category' do
      categories = RailsAiBridge::Configuration::INTROSPECTION_CATEGORY_INTROSPECTORS
      expect(categories[:domain_metadata]).to include(:non_ar_models)
    end

    it 'non_ar_models is NOT in :standard preset (by design)' do
      preset = RailsAiBridge::Configuration::PRESETS[:standard]
      expect(preset).not_to include(:non_ar_models)
    end

    it 'non_ar_models IS in :full preset' do
      preset = RailsAiBridge::Configuration::PRESETS[:full]
      expect(preset).to include(:non_ar_models)
    end

    it 'disabling domain_metadata removes non_ar_models from :full effective list' do
      introspection.preset = :full
      introspection.disabled_introspection_categories << :domain_metadata
      expect(introspection.effective_introspectors).not_to include(:non_ar_models)
    end
  end
end
