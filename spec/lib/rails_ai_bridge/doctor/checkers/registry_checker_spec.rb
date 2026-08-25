# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::RegistryChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }
  let(:registry_config) { RailsAiBridge.configuration.registry }

  describe '#call' do
    context 'when the manifest file is missing' do
      before do
        allow(registry_config).to receive(:registry_manifest_path).and_return('/nonexistent/manifest.json')
        allow(File).to receive(:exist?).with('/nonexistent/manifest.json').and_return(false)
      end

      it 'returns a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('not found')
        expect(result.fix).to include('skill-registry-guide')
      end
    end

    context 'when the manifest contains invalid JSON' do
      before do
        allow(registry_config).to receive(:registry_manifest_path).and_return('/tmp/invalid.json')
        allow(File).to receive(:exist?).with('/tmp/invalid.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/invalid.json').and_return('{ invalid json }')
        allow(RailsAiBridge::Registry::RegistryManifest).to receive(:from_file)
          .and_raise(ArgumentError, 'invalid JSON')
      end

      it 'returns a fail check' do
        result = checker.call
        expect(result.status).to eq(:fail)
        expect(result.message).to include('invalid JSON')
      end
    end

    context 'when the manifest fails schema validation' do
      before do
        allow(registry_config).to receive(:registry_manifest_path).and_return('/tmp/bad_schema.json')
        allow(File).to receive(:exist?).with('/tmp/bad_schema.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/bad_schema.json').and_return('{"version": 123}')
        allow(RailsAiBridge::Registry::RegistryManifest).to receive(:from_file)
          .and_return(instance_double(RailsAiBridge::Registry::RegistryManifest))
        allow(RailsAiBridge::Registry::RegistryManifest).to receive(:validate!)
          .and_raise(RailsAiBridge::Registry::RegistryManifest::ValidationError, "'version' must be a String")
      end

      it 'returns a fail check' do
        result = checker.call
        expect(result.status).to eq(:fail)
        expect(result.message).to include('schema validation')
        expect(result.fix).to include('skill-registry-guide')
      end
    end

    context 'when the resolver returns nil' do
      let(:manifest_hash) { { 'version' => '1.0.0', 'packs' => {}, 'default_stack' => [] } }

      before do
        allow(File).to receive(:exist?).with('/tmp/valid.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/valid.json').and_return(JSON.generate(manifest_hash))
        allow(RailsAiBridge::Registry::RegistryManifest).to receive_messages(from_file: instance_double(RailsAiBridge::Registry::RegistryManifest), validate!: manifest_hash)
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil)
        allow(registry_config).to receive_messages(registry_manifest_path: '/tmp/valid.json', lockfile_path: nil)
      end

      it 'returns a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('resolver returned nil')
        expect(result.fix).to include('git')
      end
    end

    context 'when the lockfile is configured but missing' do
      let(:manifest_hash) { { 'version' => '1.0.0', 'packs' => {}, 'default_stack' => [] } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

      before do
        allow(File).to receive(:exist?).with('/tmp/valid.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/valid.json').and_return(JSON.generate(manifest_hash))
        allow(RailsAiBridge::Registry::RegistryManifest).to receive_messages(from_file: instance_double(RailsAiBridge::Registry::RegistryManifest), validate!: manifest_hash)
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(registry_config).to receive_messages(registry_manifest_path: '/tmp/valid.json', lockfile_path: '/tmp/missing.lock')
        allow(File).to receive(:exist?).with('/tmp/missing.lock').and_return(false)
      end

      it 'returns a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('Lockfile not found')
        expect(result.fix).to include('ai:registry:lock')
      end
    end

    context 'when everything passes' do
      let(:manifest_hash) { { 'version' => '1.0.0', 'packs' => {}, 'default_stack' => [] } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

      before do
        allow(File).to receive(:exist?).with('/tmp/valid.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/valid.json').and_return(JSON.generate(manifest_hash))
        allow(RailsAiBridge::Registry::RegistryManifest).to receive_messages(from_file: instance_double(RailsAiBridge::Registry::RegistryManifest), validate!: manifest_hash)
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(registry_config).to receive_messages(registry_manifest_path: '/tmp/valid.json', lockfile_path: nil)
      end

      it 'returns a pass check' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to include('valid and resolvable')
        expect(result.fix).to be_nil
      end
    end

    context 'when everything passes with a valid lockfile' do
      let(:manifest_hash) { { 'version' => '1.0.0', 'packs' => {}, 'default_stack' => [] } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

      before do
        allow(File).to receive(:exist?).with('/tmp/valid.json').and_return(true)
        allow(File).to receive(:read).with('/tmp/valid.json').and_return(JSON.generate(manifest_hash))
        allow(RailsAiBridge::Registry::RegistryManifest).to receive_messages(from_file: instance_double(RailsAiBridge::Registry::RegistryManifest), validate!: manifest_hash)
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(registry_config).to receive_messages(registry_manifest_path: '/tmp/valid.json', lockfile_path: '/tmp/valid.lock')
        allow(File).to receive(:exist?).with('/tmp/valid.lock').and_return(true)
      end

      it 'returns a pass check' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to include('valid and resolvable')
      end
    end
  end

  describe '#resolver_reason' do
    it 'returns an empty string when resolver is not nil' do
      resolver = instance_double(RailsAiBridge::Registry::Resolver)

      expect(checker.send(:resolver_reason, resolver)).to eq('')
    end

    it 'returns a reason string when resolver is nil' do
      expect(checker.send(:resolver_reason, nil)).to include('manifest missing')
    end
  end

  describe '#call with network: true' do
    let(:manifest) do
      instance_double(
        RailsAiBridge::Registry::RegistryManifest,
        context_providers: providers
      )
    end
    let(:providers) { {} }

    before do
      allow(File).to receive(:exist?).with('/tmp/valid.json').and_return(true)
      allow(File).to receive(:read).with('/tmp/valid.json').and_return('{}')
      allow(RailsAiBridge::Registry::RegistryManifest).to receive_messages(from_file: manifest, validate!: {})
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(instance_double(RailsAiBridge::Registry::Resolver))
      allow(registry_config).to receive_messages(registry_manifest_path: '/tmp/valid.json', lockfile_path: nil)
    end

    def providers_config
      RailsAiBridge.configuration.context_providers
    end

    def success_probe_result
      RailsAiBridge::Registry::ContextProviderClient::Result.new(
        status: :success, content: nil, provenance: 'https://example.com', error: nil
      )
    end

    def error_probe_result(message = 'connection refused')
      RailsAiBridge::Registry::ContextProviderClient::Result.new(
        status: :error, content: nil, provenance: nil,
        error: RailsAiBridge::Registry::ConnectionError.new(message)
      )
    end

    context 'when context providers are disabled' do
      before { allow(providers_config).to receive(:enabled).and_return(false) }

      it 'skips network probe and reports providers disabled' do
        result = checker.call(network: true)

        expect(result.status).to eq(:pass)
        expect(result.message).to include('providers are disabled')
      end
    end

    context 'when context providers are enabled but manifest has no providers' do
      before { allow(providers_config).to receive(:enabled).and_return(true) }

      it 'skips network probe and reports no providers' do
        result = checker.call(network: true)

        expect(result.status).to eq(:pass)
        expect(result.message).to include('no context providers')
      end
    end

    context 'when all providers are reachable' do
      let(:providers) do
        {
          'billing' => build_provider(optional: false),
          'analytics' => build_provider(optional: true)
        }
      end

      before do
        allow(providers_config).to receive(:enabled).and_return(true)
        allow(checker).to receive(:probe_provider).and_return(success_probe_result)
      end

      it 'returns pass with all providers reachable' do
        result = checker.call(network: true)

        expect(result.status).to eq(:pass)
        expect(result.message).to include('reachable')
      end
    end

    context 'when an optional provider is unreachable' do
      let(:providers) do
        {
          'billing' => build_provider(optional: false),
          'analytics' => build_provider(optional: true)
        }
      end

      before do
        allow(providers_config).to receive(:enabled).and_return(true)
        allow(checker).to receive(:probe_provider) do |_name, provider|
          provider.optional? ? error_probe_result : success_probe_result
        end
      end

      it 'returns warn for optional provider failure' do
        result = checker.call(network: true)

        expect(result.status).to eq(:warn)
        expect(result.message).to include('analytics')
        expect(result.message).to include('connection refused')
      end
    end

    context 'when a required provider is unreachable' do
      let(:providers) do
        { 'billing' => build_provider(optional: false) }
      end

      before do
        allow(providers_config).to receive(:enabled).and_return(true)
        allow(checker).to receive(:probe_provider).and_return(error_probe_result)
      end

      it 'returns fail for required provider failure' do
        result = checker.call(network: true)

        expect(result.status).to eq(:fail)
        expect(result.message).to include('billing')
        expect(result.message).to include('connection refused')
      end
    end

    context 'when network: false (default)' do
      before { allow(providers_config).to receive(:enabled).and_return(true) }

      it 'does not probe providers' do
        allow(checker).to receive(:probe_provider).and_raise('should not be called')

        result = checker.call(network: false)

        expect(result.status).to eq(:pass)
        expect(result.message).to include('valid and resolvable')
      end
    end

    def build_provider(optional: false)
      RailsAiBridge::Registry::ContextProviderDefinition.new(
        type: 'mcp',
        endpoint: 'https://example.com/mcp',
        optional: optional,
        tools: []
      )
    end
  end
end
