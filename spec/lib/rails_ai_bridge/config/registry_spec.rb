# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Registry do
  describe '#initialize' do
    it 'sets default values' do
      config = described_class.new

      expect(config.registry_manifest_path).to eq('config/rails_ai_bridge_registry.json')
      expect(config.skill_cache_dir).to eq(File.expand_path('~/.rails-ai-bridge/cache'))
      expect(config.skill_packs).to be_nil
      expect(config.local_registry_paths).to eq([])
    end
  end

  describe '#registry_manifest_path' do
    it 'allows setting a custom path' do
      config = described_class.new
      config.registry_manifest_path = 'custom/registry.json'

      expect(config.registry_manifest_path).to eq('custom/registry.json')
    end
  end

  describe '#skill_cache_dir' do
    it 'allows setting a custom cache directory' do
      config = described_class.new
      config.skill_cache_dir = '/tmp/custom-cache'

      expect(config.skill_cache_dir).to eq('/tmp/custom-cache')
    end
  end

  describe '#skill_packs' do
    it 'allows setting explicit pack names' do
      config = described_class.new
      config.skill_packs = %w[rails core]

      expect(config.skill_packs).to eq(%w[rails core])
    end

    it 'allows setting to nil to trigger auto-detection' do
      config = described_class.new
      config.skill_packs = %w[rails]
      config.skill_packs = nil

      expect(config.skill_packs).to be_nil
    end
  end

  describe '#local_registry_paths' do
    it 'allows setting local registry paths' do
      config = described_class.new
      config.local_registry_paths = ['/path/to/local1', '/path/to/local2']

      expect(config.local_registry_paths).to eq(['/path/to/local1', '/path/to/local2'])
    end

    it 'defaults to empty array' do
      config = described_class.new

      expect(config.local_registry_paths).to eq([])
    end
  end
end

RSpec.describe RailsAiBridge::Configuration do
  describe '#registry' do
    it 'initializes with a Config::Registry instance' do
      config = described_class.new

      expect(config.registry).to be_a(RailsAiBridge::Config::Registry)
    end

    it 'has default registry configuration' do
      config = described_class.new

      expect(config.registry.registry_manifest_path).to eq('config/rails_ai_bridge_registry.json')
      expect(config.registry.skill_cache_dir).to eq(File.expand_path('~/.rails-ai-bridge/cache'))
      expect(config.registry.skill_packs).to be_nil
      expect(config.registry.local_registry_paths).to eq([])
    end
  end
end
