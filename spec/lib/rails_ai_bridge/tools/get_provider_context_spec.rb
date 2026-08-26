# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'spec_helper'
require 'rails_ai_bridge/registry/context_provider_definition'
require 'rails_ai_bridge/registry/context_tool_spec'
require 'rails_ai_bridge/registry/provider_request_scope'

RSpec.describe RailsAiBridge::Tools::GetProviderContext do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }
  let(:params)   { {} }

  let(:config) do
    RailsAiBridge::Config::ContextProviders.new.tap do |c|
      c.enabled = true
      c.allowed_hosts = ['example.com']
    end
  end

  let(:manifest) { instance_double(RailsAiBridge::Registry::RegistryManifest) }
  let(:provider) { build_provider(tools: [simple_tool]) }
  let(:scope) { RailsAiBridge::Registry::ProviderRequestScope.new }

  before do
    allow(manifest).to receive(:context_providers).and_return({ 'billing' => provider })
    allow(RailsAiBridge).to receive(:configuration).and_return(
      instance_double(RailsAiBridge::Configuration, context_providers: config, registry: double(registry_manifest_path: 'config/rails_ai_bridge/registry.json'),
                                                    max_tool_response_chars: nil)
    )
  end

  def simple_tool
    RailsAiBridge::Registry::ContextToolSpec.new(name: 'get_status', field: nil, arguments: nil)
  end

  def mapped_tool
    RailsAiBridge::Registry::ContextToolSpec.new(
      name: 'get_invoice', field: 'invoices', arguments: { 'limit' => 5 }
    )
  end

  def build_provider(tools:, endpoint: 'https://example.com/mcp', optional: false)
    RailsAiBridge::Registry::ContextProviderDefinition.new(
      type: 'mcp', endpoint:, optional:, tools:
    )
  end

  def success_result(content = { 'status' => 'ok' }, provenance = 'https://example.com')
    RailsAiBridge::Registry::ContextProviderClient::Result.new(
      status: :success, content:, provenance:, error: nil
    )
  end

  def error_result(error = RailsAiBridge::Registry::ConnectionError.new('connection refused'))
    RailsAiBridge::Registry::ContextProviderClient::Result.new(
      status: :error, content: nil, provenance: nil, error:
    )
  end

  def success_client(result = success_result)
    instance_double(RailsAiBridge::Registry::ContextProviderClient, call_tool: result)
  end

  def failing_client
    instance_double(RailsAiBridge::Registry::ContextProviderClient, call_tool: error_result)
  end

  # ── disabled providers ─────────────────────────────────────────────────────

  context 'when context_providers.enabled is false' do
    before { config.enabled = false }

    it 'returns a setup message without making network calls' do
      expect(content).to include('disabled')
      expect(content).to include('enabled')
    end
  end

  # ── no manifest ─────────────────────────────────────────────────────────────

  context 'when no manifest is found' do
    before do
      allow(described_class).to receive(:load_manifest).and_return(nil)
    end

    it 'returns a setup message mentioning the manifest' do
      expect(content).to include('manifest')
    end
  end

  # ── no providers declared ───────────────────────────────────────────────────

  context 'when manifest has no context providers' do
    before do
      allow(described_class).to receive(:load_manifest).and_return(manifest)
      allow(manifest).to receive(:context_providers).and_return({})
    end

    it 'returns a message stating no providers are declared' do
      expect(content).to include('No context providers')
    end
  end

  # ── fetch all providers ─────────────────────────────────────────────────────

  context 'when fetching all providers' do
    let(:params) { {} }

    before do
      allow(described_class).to receive_messages(load_manifest: manifest, build_aggregator: RailsAiBridge::Registry::ContextAggregator.new(
        manifest:, config:, client_factory: ->(_p) { success_client }, scope:
      ))
    end

    it 'returns provider results in the response' do
      expect(content).to include('billing')
      expect(content).to include('get_status')
    end

    it 'includes source provenance information' do
      expect(content).to include('Source')
      expect(content).to include('billing')
    end
  end

  # ── fetch single provider ───────────────────────────────────────────────────

  context 'when fetching a single provider' do
    let(:params) { { provider: 'billing' } }

    before do
      allow(described_class).to receive_messages(load_manifest: manifest, build_aggregator: RailsAiBridge::Registry::ContextAggregator.new(
        manifest:, config:, client_factory: ->(_p) { success_client }, scope:
      ))
    end

    it 'returns results for only the requested provider' do
      expect(content).to include('billing')
    end
  end

  # ── unknown provider ────────────────────────────────────────────────────────

  context 'when the provider name is unknown' do
    let(:params) { { provider: 'nonexistent' } }

    before do
      allow(described_class).to receive(:load_manifest).and_return(manifest)
    end

    it 'returns an error message naming the provider' do
      expect(content).to include('nonexistent')
      expect(content).to include('not found').or include('unknown')
    end
  end

  # ── required provider failure ───────────────────────────────────────────────

  context 'when a required provider fails' do
    let(:params) { {} }

    before do
      allow(described_class).to receive_messages(load_manifest: manifest, build_aggregator: RailsAiBridge::Registry::ContextAggregator.new(
        manifest:, config:, client_factory: ->(_p) { failing_client }, scope:
      ))
    end

    it 'reports the failure in the response' do
      expect(content).to include('billing')
      expect(content).to include('connection refused').or include('error').or include('failed')
    end
  end

  # ── optional provider failure ───────────────────────────────────────────────

  context 'when an optional provider fails' do
    let(:params) { {} }
    let(:provider) { build_provider(tools: [simple_tool], optional: true) }

    before do
      allow(described_class).to receive_messages(load_manifest: manifest, build_aggregator: RailsAiBridge::Registry::ContextAggregator.new(
        manifest:, config:, client_factory: ->(_p) { failing_client }, scope:
      ))
    end

    it 'reports a warning without blocking the response' do
      expect(content).to include('billing')
      expect(content).to include('Partial Failure').or include('warning').or include('unreachable')
    end
  end

  # ── mapped tools ────────────────────────────────────────────────────────────

  context 'with mapped tools' do
    let(:provider) { build_provider(tools: [mapped_tool]) }

    before do
      allow(described_class).to receive_messages(load_manifest: manifest, build_aggregator: RailsAiBridge::Registry::ContextAggregator.new(
        manifest:, config:,
        client_factory: ->(_p) { success_client(success_result([{ 'id' => 1 }])) },
        scope:
      ))
    end

    it 'uses the declared field name in the output' do
      expect(content).to include('invoices')
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
