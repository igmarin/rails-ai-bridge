# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'rails_ai_bridge/registry/pack_resolver'
require 'rails_ai_bridge/registry/skill_source_resolver'
require 'rails_ai_bridge/registry/resolver'

RSpec.describe RailsAiBridge::Registry::PackResolver do
  let(:cache_dir) { Dir.mktmpdir }
  let(:mock_git_runner) { instance_double(RailsAiBridge::Registry::GitRunner) }
  let(:source_resolver) { RailsAiBridge::Registry::SkillSourceResolver.new(cache_dir, mock_git_runner) }

  before do
    # Stub PackDetector class method
    allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])
  end

  after do
    FileUtils.rm_rf(cache_dir)
  end

  # Helper to create a mock directory.json file
  def create_mock_tile(base_path, name: 'test-pack', skills: {}, agents: {})
    tile_path = File.join(base_path, 'directory.json')
    tile_data = {
      'name' => name,
      'version' => '1.0.0',
      'summary' => "Test pack #{name}",
      'depends_on' => [],
      'skills' => skills,
      'agents' => agents,
      'deprecated_skills' => {}
    }
    File.write(tile_path, JSON.generate(tile_data))
  end

  describe '#initialize' do
    it 'accepts a SkillSourceResolver' do
      service = described_class.new(source_resolver)
      expect(service.instance_variable_get(:@source_resolver)).to eq(source_resolver)
    end
  end

  describe '#resolve' do
    context 'when explicit pack is not defined in manifest' do
      it 'raises an error' do
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: {},
          default_stack: []
        )

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['missing_pack'], nil) }
          .to raise_error(/Pack 'missing_pack' not defined in registry manifest/)
      end
    end

    context 'when pack is marked as always_loaded' do
      it 'loads the pack even without explicit request' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: true,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        # Mock the git runner to create a mock tile
        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'core')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, nil, nil)

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to eq('core')
      end

      it 'does not duplicate pack when explicitly requested' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: true,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'core')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, ['core'], nil)

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to eq('core')
      end
    end

    context 'when explicit packs are provided' do
      it 'loads the specified packs' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'core')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, ['core'], nil)

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to eq('core')
      end
    end

    context 'when no explicit packs and framework is detected' do
      it 'auto-detects and loads framework-specific packs' do
        packs = {
          'rails' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/rails',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'rails')
        end
        allow(mock_git_runner).to receive(:pull_repo)
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([RailsAiBridge::Registry::DetectedFramework::Rails])

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, nil, nil)

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to eq('rails')
      end
    end

    context 'when no framework detected and default_stack exists' do
      it 'loads the default stack' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: ['core']
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'core')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, nil, nil)

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to eq('core')
      end
    end

    context 'when local registries are provided' do
      it 'loads local registries with priority 0' do
        local_dir = Dir.mktmpdir
        create_mock_tile(local_dir, name: 'local-pack')

        packs = {}

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, nil, [local_dir])

        expect(resolver.active_packs.length).to eq(1)
        expect(resolver.active_packs.first.name).to start_with('local_')
        expect(resolver.active_packs.first.priority).to eq(0)

        FileUtils.rm_rf(local_dir)
      end
    end

    context 'priority assignment' do
      it 'assigns correct priorities based on pack name' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          ),
          'rails' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/rails',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          ),
          'other' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/other',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          pack_name = dest.split('/').last
          create_mock_tile(dest, name: pack_name)
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, %w[core rails other], nil)

        priorities = resolver.active_packs.to_h { |p| [p.name, p.priority] }

        expect(priorities['rails']).to eq(10)
        expect(priorities['core']).to eq(20)
        expect(priorities['other']).to eq(30)
      end

      it 'assigns priority 10 to hanami packs' do
        packs = {
          'hanami' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/hanami',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: 'hanami')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, ['hanami'], nil)

        expect(resolver.active_packs.first.priority).to eq(10)
      end
    end

    context 'error handling' do
      it 'handles tile file read errors' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          # Don't create directory.json to trigger read error
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['core'], nil) }
          .to raise_error(/Failed to read tile manifest for pack 'core'/)
      end

      it 'handles local registry tile file read errors' do
        local_dir = Dir.mktmpdir
        # Don't create tile.json to trigger read error

        packs = {}

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, nil, [local_dir]) }
          .to raise_error(/Failed to read local registry tile manifest/)

        FileUtils.rm_rf(local_dir)
      end

      it 'handles tile JSON parse errors' do
        packs = {
          'core' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/core',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: [],
            ref: nil
          )
        }

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          # Create invalid JSON
          File.write(File.join(dest, 'directory.json'), 'invalid json')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['core'], nil) }
          .to raise_error(JSON::ParserError)
      end

      it 'handles local registry JSON parse errors' do
        local_dir = Dir.mktmpdir
        # Create invalid JSON
        File.write(File.join(local_dir, 'directory.json'), 'invalid json')

        packs = {}

        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0',
          packs: packs,
          default_stack: []
        )

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, nil, [local_dir]) }
          .to raise_error(JSON::ParserError)

        FileUtils.rm_rf(local_dir)
      end
    end
  end
end
