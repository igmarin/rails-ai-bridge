# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe RailsAiBridge::Registry do
  describe '.build_resolver' do
    let(:config) { RailsAiBridge::Config::Registry.new }

    # Each example uses a fresh config pointing at different paths.
    # The module-level cache is keyed by the single cached Resolver, not by config,
    # so we must invalidate between examples to prevent cross-test pollution.
    before { described_class.invalidate_resolver_cache! }
    after  { described_class.invalidate_resolver_cache! }

    context 'when manifest file does not exist' do
      it 'returns nil' do
        config.registry_manifest_path = '/nonexistent/path/registry.json'

        expect(described_class.build_resolver(config)).to be_nil
      end
    end

    context 'when manifest file exists' do
      let(:tmp_dir) { Dir.mktmpdir }
      let(:manifest_path) { File.join(tmp_dir, 'registry.json') }
      let(:cache_dir) { File.join(tmp_dir, 'cache') }

      after { FileUtils.rm_rf(tmp_dir) }

      before do
        config.registry_manifest_path = manifest_path
        config.skill_cache_dir = cache_dir
        config.skill_packs = nil
        config.local_registry_paths = []
        # Prevent auto-detection from picking up this project's own Gemfile
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])
      end

      context 'with an empty manifest (no packs)' do
        before do
          File.write(manifest_path, JSON.generate({
                                                    'version' => '1.0.0',
                                                    'packs' => {},
                                                    'default_stack' => []
                                                  }))
        end

        it 'returns a Resolver instance' do
          result = described_class.build_resolver(config)

          expect(result).to be_a(RailsAiBridge::Registry::Resolver)
        end

        it 'returns a resolver with no active packs' do
          result = described_class.build_resolver(config)

          expect(result.active_packs).to be_empty
        end
      end

      context 'with local_registry_paths set' do
        let(:local_dir) { File.join(tmp_dir, 'local_pack') }

        before do
          FileUtils.mkdir_p(local_dir)
          File.write(File.join(local_dir, 'directory.json'), JSON.generate({
                                                                             'name' => 'local-test-pack',
                                                                             'version' => '0.1.0',
                                                                             'summary' => 'Local test pack',
                                                                             'depends_on' => [],
                                                                             'skills' => {},
                                                                             'agents' => {},
                                                                             'deprecated_skills' => {}
                                                                           }))
          File.write(manifest_path, JSON.generate({
                                                    'version' => '1.0.0',
                                                    'packs' => {},
                                                    'default_stack' => []
                                                  }))
          config.local_registry_paths = [local_dir]
        end

        it 'returns a resolver with the local pack loaded' do
          result = described_class.build_resolver(config)

          expect(result).to be_a(RailsAiBridge::Registry::Resolver)
          expect(result.active_packs.length).to eq(1)
          expect(result.active_packs.first.priority).to eq(0)
        end
      end

      context 'when local_registry_paths is empty' do
        before do
          File.write(manifest_path, JSON.generate({
                                                    'version' => '1.0.0',
                                                    'packs' => {},
                                                    'default_stack' => []
                                                  }))
        end

        it 'passes nil to PackResolver (not an empty array)' do
          # Spy on PackResolver by injecting a recording double that delegates to a real instance
          received_local_paths = :not_called
          real_pack_resolver = RailsAiBridge::Registry::PackResolver.new(
            RailsAiBridge::Registry::SkillSourceResolver.new(cache_dir)
          )
          spy_resolver = instance_double(RailsAiBridge::Registry::PackResolver)
          allow(spy_resolver).to receive(:resolve) do |manifest, packs, local_paths|
            received_local_paths = local_paths
            real_pack_resolver.resolve(manifest, packs, local_paths)
          end
          allow(RailsAiBridge::Registry::PackResolver).to receive(:new).and_return(spy_resolver)

          described_class.build_resolver(config)

          expect(received_local_paths).to be_nil
        end
      end
    end

    context 'when called with default config and no manifest file present' do
      it 'returns nil gracefully' do
        allow(RailsAiBridge.configuration.registry).to receive(:registry_manifest_path)
          .and_return('/nonexistent/path/registry.json')

        result = described_class.build_resolver

        expect(result).to be_nil
      end
    end

    # ── R2: ResolutionError returns nil instead of raising ────────────────────

    context 'when the manifest is malformed (missing required field)' do
      let(:bad_manifest_path) { File.join(Dir.mktmpdir, 'registry.json') }

      before do
        File.write(bad_manifest_path, JSON.generate({ 'packs' => {} })) # missing 'version'
        config.registry_manifest_path = bad_manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])
      end

      after { FileUtils.rm_rf(File.dirname(bad_manifest_path)) }

      it 'returns nil rather than raising' do
        expect { described_class.build_resolver(config) }.not_to raise_error
        expect(described_class.build_resolver(config)).to be_nil
      end
    end

    context 'when called with default config and manifest file present' do
      it 'returns a non-nil resolver' do
        Dir.mktmpdir do |dir|
          manifest_path = File.join(dir, 'registry.json')
          File.write(manifest_path, JSON.generate(
                                      version: '1.0.0',
                                      packs: {},
                                      default_stack: []
                                    ))

          config = RailsAiBridge.configuration.registry.dup
          allow(config).to receive_messages(registry_manifest_path: manifest_path, local_registry_paths: [], skill_packs: [])

          result = described_class.build_resolver(config)

          expect(result).not_to be_nil
        end
      end
    end
  end

  describe '.with_request_resolver' do
    let(:config) { RailsAiBridge::Config::Registry.new }

    before do
      described_class.invalidate_resolver_cache!
      described_class.clear_request_resolver!
    end

    after do
      described_class.invalidate_resolver_cache!
      described_class.clear_request_resolver!
    end

    it 'memoizes the resolver across multiple build_resolver calls within the block' do
      calls = 0
      allow(described_class).to receive(:build_resolver_uncached).and_wrap_original do |original, cfg|
        calls += 1
        original.call(cfg)
      end

      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))
        config.registry_manifest_path = manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])

        described_class.invalidate_resolver_cache!

        described_class.with_request_resolver do
          first = described_class.build_resolver(config)
          second = described_class.build_resolver(config)

          expect(first).to equal(second)
          expect(calls).to eq(1)
        end
      end
    end

    it 'clears the request-scoped resolver after the block exits' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))
        config.registry_manifest_path = manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])

        described_class.invalidate_resolver_cache!

        described_class.with_request_resolver do
          described_class.build_resolver(config)
        end

        expect(described_class.send(:request_resolver?)).to be(false)
      end
    end

    it 'clears the request-scoped resolver even when the block raises' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))
        config.registry_manifest_path = manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])

        described_class.invalidate_resolver_cache!

        expect do
          described_class.with_request_resolver do
            described_class.build_resolver(config)
            raise 'boom'
          end
        end.to raise_error('boom')

        expect(described_class.send(:request_resolver?)).to be(false)
      end
    end

    it 'does not memoize nil results (manifest missing)' do
      config.registry_manifest_path = '/nonexistent/path/registry.json'

      described_class.with_request_resolver do
        first = described_class.build_resolver(config)
        second = described_class.build_resolver(config)

        expect(first).to be_nil
        expect(second).to be_nil
        expect(described_class.send(:request_resolver?)).to be(false)
      end
    end

    it 'marks the request scope as active inside the block' do
      described_class.with_request_resolver do
        expect(described_class.send(:request_active?)).to be(true)
      end
    end

    it 'stores the resolver in the request scope so later calls reuse it' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))
        config.registry_manifest_path = manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []
        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])

        described_class.invalidate_resolver_cache!

        described_class.with_request_resolver do
          described_class.build_resolver(config)
          expect(described_class.send(:request_resolver?)).to be(true)
        end
      end
    end

    it 'returns nil from request_resolver before the first build (sentinel active)' do
      described_class.with_request_resolver do
        expect(described_class.send(:request_resolver)).to be_nil
        expect(described_class.send(:request_resolver?)).to be(false)
      end
    end
  end

  describe '.write_lockfile' do
    let(:config) { RailsAiBridge::Config::Registry.new }

    it 'raises ArgumentError when the manifest file does not exist' do
      config.registry_manifest_path = '/nonexistent/path/registry.json'

      expect { described_class.write_lockfile(config) }.to raise_error(ArgumentError, /Registry manifest not found/)
    end

    it 'writes the lockfile when the manifest exists' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        lockfile_path = File.join(dir, 'registry.lock')
        cache_dir = File.join(dir, 'cache')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))

        config.registry_manifest_path = manifest_path
        config.lockfile_path = lockfile_path
        config.skill_cache_dir = cache_dir

        allow(RailsAiBridge::Registry::Lockfile).to receive(:write).and_return(nil)

        described_class.write_lockfile(config)

        expect(RailsAiBridge::Registry::Lockfile).to have_received(:write).with(
          lockfile_path,
          anything,
          anything
        )
      end
    end
  end

  describe '.build_resolver_uncached when Rails.logger is nil' do
    let(:config) { RailsAiBridge::Config::Registry.new }

    it 'logs nothing and returns nil without raising' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, JSON.generate(version: '1.0.0', packs: {}, default_stack: []))
        config.registry_manifest_path = manifest_path
        config.skill_packs = nil
        config.local_registry_paths = []

        allow(RailsAiBridge::Registry::PackDetector).to receive(:detect).and_return([])
        allow(RailsAiBridge::Registry::PackResolver).to receive(:new).and_raise(
          RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, 'boom'
        )
        allow(Rails).to receive(:logger).and_return(nil)

        described_class.invalidate_resolver_cache!

        expect { described_class.build_resolver(config) }.not_to raise_error
        expect(described_class.build_resolver(config)).to be_nil
      end
    end
  end
end
