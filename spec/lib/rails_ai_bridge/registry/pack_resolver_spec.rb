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

  # Helper to build a PackDefinition for a dummy source
  def build_pack(name, depends_on: [])
    RailsAiBridge::Registry::PackDefinition.new(
      source: "dummy/#{name}",
      tile: 'directory.json',
      always_loaded: false,
      depends_on: depends_on,
      ref: nil
    )
  end

  # Stubs clone/pull so each dummy source materializes its own tile manifest
  def stub_pack_clones
    allow(mock_git_runner).to receive(:clone_repo) do |url, dest|
      FileUtils.mkdir_p(dest)
      create_mock_tile(dest, name: url.split('/').last)
    end
    allow(mock_git_runner).to receive(:pull_repo)
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

    context 'when Hanami framework is detected' do
      it 'auto-detects and loads the hanami pack' do
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
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect)
          .and_return([RailsAiBridge::Registry::DetectedFramework::Hanami])

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, nil, nil)

        expect(resolver.active_packs.first.name).to eq('hanami')
      end
    end

    context 'when an unknown framework is detected' do
      it 'does not load any framework pack but still loads explicit packs' do
        packs = {
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )
        stub_pack_clones
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect)
          .and_return([double('UnknownFramework')])

        service = described_class.new(source_resolver)
        resolver = service.resolve(manifest, ['core'], nil)

        # Unknown framework does not match Rails or Hanami, so only explicit packs load
        expect(resolver.active_packs.map(&:name)).to contain_exactly('core')
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

    context 'lockfile verification' do
      around do |example|
        saved_mode = RailsAiBridge.configuration.registry.lockfile_verification
        example.run
      ensure
        RailsAiBridge.configuration.registry.lockfile_verification = saved_mode
      end

      it 'raises when the resolved commit does not match the lockfile in strict mode' do
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
        allow(source_resolver).to receive(:current_commit).and_return('mismatch-sha')

        lockfile = RailsAiBridge::Registry::Lockfile.new(
          'core' => RailsAiBridge::Registry::Lockfile::Entry.new(
            pack_name: 'core',
            source: 'dummy/core',
            ref: nil,
            commit_sha: 'expected-sha'
          )
        )

        RailsAiBridge.configuration.registry.lockfile_verification = :strict
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, lockfile)

        expect { service.resolve(manifest, ['core'], nil) }
          .to raise_error(/Lockfile mismatch for pack 'core'/)
      end

      it 'warns and continues in warn mode' do
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
        allow(source_resolver).to receive(:current_commit).and_return('mismatch-sha')

        lockfile = RailsAiBridge::Registry::Lockfile.new(
          'core' => RailsAiBridge::Registry::Lockfile::Entry.new(
            pack_name: 'core',
            source: 'dummy/core',
            ref: nil,
            commit_sha: 'expected-sha'
          )
        )

        RailsAiBridge.configuration.registry.lockfile_verification = :warn
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, lockfile)

        expect { service.resolve(manifest, ['core'], nil) }.to output(/Lockfile mismatch for pack 'core'/).to_stderr
      end

      it 'skips verification when disabled' do
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
        allow(source_resolver).to receive(:current_commit).and_return('mismatch-sha')

        lockfile = RailsAiBridge::Registry::Lockfile.new(
          'core' => RailsAiBridge::Registry::Lockfile::Entry.new(
            pack_name: 'core',
            source: 'dummy/core',
            ref: nil,
            commit_sha: 'expected-sha'
          )
        )

        RailsAiBridge.configuration.registry.lockfile_verification = :disabled
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, lockfile)

        expect { service.resolve(manifest, ['core'], nil) }.not_to output.to_stderr
      end

      it 'skips verification entirely when no lockfile is provided' do
        packs = {
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )
        stub_pack_clones

        # No lockfile passed to constructor
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, nil)

        result = service.resolve(manifest, ['core'], nil)
        expect(result.active_packs.map(&:name)).to contain_exactly('core')
      end

      it 'skips a pack that has no lockfile entry' do
        packs = {
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )
        stub_pack_clones
        allow(source_resolver).to receive(:current_commit).and_return('sha1')

        # Lockfile with no entry for 'core'
        lockfile = RailsAiBridge::Registry::Lockfile.new({})

        RailsAiBridge.configuration.registry.lockfile_verification = :strict
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, lockfile)

        result = service.resolve(manifest, ['core'], nil)
        expect(result.active_packs.map(&:name)).to contain_exactly('core')
      end

      it 'passes when the resolved commit matches the lockfile entry' do
        packs = {
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )
        stub_pack_clones
        allow(source_resolver).to receive(:current_commit).and_return('matching-sha')

        lockfile = RailsAiBridge::Registry::Lockfile.new(
          'core' => RailsAiBridge::Registry::Lockfile::Entry.new(
            pack_name: 'core', source: 'dummy/core', ref: nil, commit_sha: 'matching-sha'
          )
        )

        RailsAiBridge.configuration.registry.lockfile_verification = :strict
        service = described_class.new(source_resolver, RailsAiBridge::Registry::PackDetector, lockfile)

        result = service.resolve(manifest, ['core'], nil)
        expect(result.active_packs.map(&:name)).to contain_exactly('core')
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

      it 'does not raise when Rails.logger is nil and tile manifest is missing' do
        packs = {
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )

        allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          # Don't create directory.json to trigger read error
        end
        allow(mock_git_runner).to receive(:pull_repo)
        allow(Rails).to receive(:logger).and_return(nil)

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
          .to raise_error(ArgumentError, /invalid JSON/)
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
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /invalid JSON/)

        FileUtils.rm_rf(local_dir)
      end
    end
  end

  describe '#warn_missing_dependencies (via #resolve)' do
    def build_manifest_with_dependency(depends_on)
      packs = {
        'pack-with-dep' => RailsAiBridge::Registry::PackDefinition.new(
          source: 'dummy/pack-with-dep',
          tile: 'directory.json',
          always_loaded: false,
          depends_on: depends_on,
          ref: nil
        )
      }

      RailsAiBridge::Registry::RegistryManifest.new(
        version: '1.0.0',
        packs: packs,
        default_stack: []
      )
    end

    before do
      allow(mock_git_runner).to receive(:clone_repo) do |_url, dest|
        FileUtils.mkdir_p(dest)
        create_mock_tile(dest, name: 'pack-with-dep')
      end
      allow(mock_git_runner).to receive(:pull_repo)
    end

    context 'when an active pack declares a single missing dependency' do
      it 'emits a stderr warning naming the pack and the missing dependency' do
        manifest = build_manifest_with_dependency(['missing-dep'])
        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['pack-with-dep'], nil) }
          .to output(
            /\[rails-ai-bridge\] Pack 'pack-with-dep' depends on 'missing-dep' which is not in the active pack set/
          ).to_stderr
      end

      it 'uses singular grammar and points at skill_packs / always_loaded' do
        manifest = build_manifest_with_dependency(['missing-dep'])
        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['pack-with-dep'], nil) }
          .to output(/which is not in the active pack set\. Add it to skill_packs or always_loaded/m).to_stderr
      end

      it 'still loads the pack despite the missing dependency' do
        manifest = build_manifest_with_dependency(['missing-dep'])
        service = described_class.new(source_resolver)

        resolver = nil
        expect { resolver = service.resolve(manifest, ['pack-with-dep'], nil) }
          .to output(/depends on/).to_stderr

        expect(resolver.active_packs.map(&:name)).to include('pack-with-dep')
      end

      it 'does not write to stdout' do
        manifest = build_manifest_with_dependency(['missing-dep'])
        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['pack-with-dep'], nil) }
          .not_to output.to_stdout
      end
    end

    context 'when an active pack declares multiple missing dependencies' do
      it 'lists every missing dependency and uses plural grammar' do
        manifest = build_manifest_with_dependency(%w[missing-one missing-two])
        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, ['pack-with-dep'], nil) }
          .to output(
            /depends on 'missing-one', 'missing-two' which are not in the active pack set\. Add them to skill_packs/m
          ).to_stderr
      end
    end

    context 'when all declared dependencies are present in the active set' do
      it 'does not warn' do
        packs = {
          'pack-with-dep' => RailsAiBridge::Registry::PackDefinition.new(
            source: 'dummy/pack-with-dep',
            tile: 'directory.json',
            always_loaded: false,
            depends_on: ['core'],
            ref: nil
          ),
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

        allow(mock_git_runner).to receive(:clone_repo) do |url, dest|
          FileUtils.mkdir_p(dest)
          create_mock_tile(dest, name: url.include?('core') ? 'core' : 'pack-with-dep')
        end
        allow(mock_git_runner).to receive(:pull_repo)

        service = described_class.new(source_resolver)

        expect { service.resolve(manifest, %w[pack-with-dep core], nil) }
          .not_to output.to_stderr
      end
    end

    describe '#resolve with auto_load_dependencies enabled' do
      around do |example|
        registry = RailsAiBridge.configuration.registry
        original = registry.auto_load_dependencies
        registry.auto_load_dependencies = true
        example.run
      ensure
        registry.auto_load_dependencies = original
      end

      context 'when an active pack declares a dependency on another defined pack' do
        it 'loads the dependency transitively' do
          packs = {
            'app' => build_pack('app', depends_on: ['core']),
            'core' => build_pack('core')
          }
          manifest = RailsAiBridge::Registry::RegistryManifest.new(
            version: '1.0.0', packs: packs, default_stack: []
          )
          stub_pack_clones

          resolver = described_class.new(source_resolver).resolve(manifest, ['app'], nil)

          expect(resolver.active_packs.map(&:name)).to contain_exactly('app', 'core')
        end
      end

      context 'with a two-level dependency chain' do
        it 'loads every level' do
          packs = {
            'app' => build_pack('app', depends_on: ['middleware']),
            'middleware' => build_pack('middleware', depends_on: ['core']),
            'core' => build_pack('core')
          }
          manifest = RailsAiBridge::Registry::RegistryManifest.new(
            version: '1.0.0', packs: packs, default_stack: []
          )
          stub_pack_clones

          resolver = described_class.new(source_resolver).resolve(manifest, ['app'], nil)

          expect(resolver.active_packs.map(&:name)).to contain_exactly('app', 'middleware', 'core')
        end
      end

      context 'when packs form a dependency cycle' do
        it 'warns about the cycle and still loads both packs' do
          packs = {
            'alpha' => build_pack('alpha', depends_on: ['beta']),
            'beta' => build_pack('beta', depends_on: ['alpha'])
          }
          manifest = RailsAiBridge::Registry::RegistryManifest.new(
            version: '1.0.0', packs: packs, default_stack: []
          )
          stub_pack_clones

          resolver = nil
          expect { resolver = described_class.new(source_resolver).resolve(manifest, ['alpha'], nil) }
            .to output(/[Cc]ircular dependency.*alpha.*beta/m).to_stderr

          expect(resolver.active_packs.map(&:name)).to contain_exactly('alpha', 'beta')
        end
      end

      context 'when a dependency is not defined in the manifest' do
        it 'leaves it out of the active set and keeps the missing-dependency warning' do
          packs = { 'app' => build_pack('app', depends_on: ['ghost']) }
          manifest = RailsAiBridge::Registry::RegistryManifest.new(
            version: '1.0.0', packs: packs, default_stack: []
          )
          stub_pack_clones

          resolver = nil
          expect { resolver = described_class.new(source_resolver).resolve(manifest, ['app'], nil) }
            .to output(/depends on 'ghost'/).to_stderr

          expect(resolver.active_packs.map(&:name)).to contain_exactly('app')
        end
      end

      context 'when a local registry pack is active but not in manifest.packs' do
        it 'handles the nil gracefully during dependency expansion' do
          local_dir = Dir.mktmpdir
          create_mock_tile(local_dir, name: 'local-pack')

          packs = { 'app' => build_pack('app') }
          manifest = RailsAiBridge::Registry::RegistryManifest.new(
            version: '1.0.0', packs: packs, default_stack: []
          )
          stub_pack_clones

          resolver = described_class.new(source_resolver).resolve(manifest, nil, [local_dir])

          # Local pack name is derived from path hash, not from tile name
          expect(resolver.active_packs.length).to eq(1)
          expect(resolver.active_packs.first.name).to start_with('local_')
        ensure
          FileUtils.rm_rf(local_dir)
        end
      end
    end

    describe '#resolve with auto_load_dependencies disabled (default)' do
      it 'does not load dependencies transitively' do
        packs = {
          'app' => build_pack('app', depends_on: ['core']),
          'core' => build_pack('core')
        }
        manifest = RailsAiBridge::Registry::RegistryManifest.new(
          version: '1.0.0', packs: packs, default_stack: []
        )
        stub_pack_clones

        resolver = nil
        expect { resolver = described_class.new(source_resolver).resolve(manifest, ['app'], nil) }
          .to output(/depends on 'core'/).to_stderr

        expect(resolver.active_packs.map(&:name)).to contain_exactly('app')
      end
    end
  end
end
