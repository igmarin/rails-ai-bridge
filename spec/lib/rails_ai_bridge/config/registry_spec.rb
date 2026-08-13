# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Registry do
  describe '#initialize' do
    it 'sets default values' do
      config = described_class.new

      expect(config.registry_manifest_path).to eq('config/rails_ai_bridge/registry.json')
      expect(config.skill_cache_dir).to eq(File.expand_path('~/.rails-ai-bridge/cache'))
      expect(config.skill_packs).to be_nil
      expect(config.local_registry_paths).to eq([])
      expect(config.auto_load_dependencies).to be(false)
    end
  end

  describe '#auto_load_dependencies' do
    it 'allows enabling transitive dependency loading' do
      config = described_class.new
      config.auto_load_dependencies = true

      expect(config.auto_load_dependencies).to be(true)
    end
  end

  describe '#registry_manifest_path' do
    it 'allows setting a custom path' do
      config = described_class.new
      config.registry_manifest_path = 'custom/registry.json'

      expect(config.registry_manifest_path).to eq('custom/registry.json')
    end

    context 'with backward-compatibility fallback' do
      let(:config) { described_class.new }

      it 'returns the new default when neither path exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_REGISTRY_MANIFEST_PATH).and_return(false)
        allow(File).to receive(:exist?).with(described_class::LEGACY_REGISTRY_MANIFEST_PATH).and_return(false)

        expect(config.registry_manifest_path).to eq(described_class::DEFAULT_REGISTRY_MANIFEST_PATH)
      end

      it 'falls back to the legacy path when only the legacy path exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_REGISTRY_MANIFEST_PATH).and_return(false)
        allow(File).to receive(:exist?).with(described_class::LEGACY_REGISTRY_MANIFEST_PATH).and_return(true)

        expect(config.registry_manifest_path).to eq(described_class::LEGACY_REGISTRY_MANIFEST_PATH)
      end

      it 'uses the new default when it exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_REGISTRY_MANIFEST_PATH).and_return(true)

        expect(config.registry_manifest_path).to eq(described_class::DEFAULT_REGISTRY_MANIFEST_PATH)
      end

      it 'does not apply fallback when a custom path is set' do
        config.registry_manifest_path = 'custom/registry.json'

        expect(config.registry_manifest_path).to eq('custom/registry.json')
      end
    end
  end

  describe '#lockfile_path' do
    it 'allows setting a custom path' do
      config = described_class.new
      config.lockfile_path = 'custom/registry.lock'

      expect(config.lockfile_path).to eq('custom/registry.lock')
    end

    it 'allows disabling lockfile verification with nil' do
      config = described_class.new
      config.lockfile_path = nil

      expect(config.lockfile_path).to be_nil
    end

    context 'with backward-compatibility fallback' do
      let(:config) { described_class.new }

      it 'returns the new default when neither path exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_LOCKFILE_PATH).and_return(false)
        allow(File).to receive(:exist?).with(described_class::LEGACY_LOCKFILE_PATH).and_return(false)

        expect(config.lockfile_path).to eq(described_class::DEFAULT_LOCKFILE_PATH)
      end

      it 'falls back to the legacy path when only the legacy path exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_LOCKFILE_PATH).and_return(false)
        allow(File).to receive(:exist?).with(described_class::LEGACY_LOCKFILE_PATH).and_return(true)

        expect(config.lockfile_path).to eq(described_class::LEGACY_LOCKFILE_PATH)
      end

      it 'uses the new default when it exists' do
        allow(File).to receive(:exist?).with(described_class::DEFAULT_LOCKFILE_PATH).and_return(true)

        expect(config.lockfile_path).to eq(described_class::DEFAULT_LOCKFILE_PATH)
      end
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

      expect(config.registry.registry_manifest_path).to eq('config/rails_ai_bridge/registry.json')
      expect(config.registry.skill_cache_dir).to eq(File.expand_path('~/.rails-ai-bridge/cache'))
      expect(config.registry.skill_packs).to be_nil
      expect(config.registry.local_registry_paths).to eq([])
    end
  end
end
