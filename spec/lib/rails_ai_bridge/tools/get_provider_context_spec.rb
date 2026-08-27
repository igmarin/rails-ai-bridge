# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'spec_helper'
require 'faraday'
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
      allow(described_class).to receive(:load_manifest).and_return(:missing)
    end

    it 'returns a setup message mentioning the manifest' do
      expect(content).to include('No registry manifest found')
    end
  end

  # ── malformed manifest ──────────────────────────────────────────────────────

  context 'when the manifest is malformed JSON' do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('config/rails_ai_bridge/registry.json').and_return(true)
      allow(RailsAiBridge::Registry::RegistryManifest).to receive(:from_file).and_raise(JSON::ParserError.new('unexpected token'))
    end

    it 'returns a malformed manifest message instead of raising' do
      expect(content).to include('invalid')
      expect(content).to include('could not be parsed')
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

  # ── error without provider_name ──────────────────────────────────────────────

  context 'when an error has no provider_name set' do
    let(:error_without_name) { RailsAiBridge::Registry::ConnectionError.new('connection refused') }
    let(:aggregate_result) do
      RailsAiBridge::Registry::ContextAggregator::AggregateResult.new(
        results: {}, failures: [error_without_name], status: :error, elapsed_ms: 0
      )
    end

    it 'renders unknown as the provider name in the formatter' do
      output = described_class::ResultFormatter.new(aggregate_result).format
      expect(output).to include('unknown')
      expect(output).to include('ConnectionError')
    end
  end

  # ── ResultFormatter branch coverage ──────────────────────────────────────────

  describe RailsAiBridge::Tools::GetProviderContext::ResultFormatter do
    let(:success_result) do
      RailsAiBridge::Registry::ContextAggregator::AggregateResult.new(
        results: { 'billing' => { 'status' => 'ok' } }, failures: [], status: :success, elapsed_ms: 42
      )
    end

    it 'formats a single provider error header' do
      error_result = RailsAiBridge::Registry::ContextAggregator::AggregateResult.new(
        results: {}, failures: [], status: :error, elapsed_ms: 10
      )
      output = described_class.new(error_result, provider_name: 'billing').format
      expect(output).to include('Provider Context: billing')
      expect(output).to include('FAILED')
    end

    it 'formats Array data as a list' do
      array_result = RailsAiBridge::Registry::ContextAggregator::AggregateResult.new(
        results: { 'billing' => [{ 'id' => 1 }, { 'id' => 2 }] }, failures: [], status: :success, elapsed_ms: 5
      )
      output = described_class.new(array_result).format
      expect(output).to include('"id": 1')
      expect(output).to include('"id": 2')
    end

    it 'formats scalar data with to_s' do
      scalar_result = RailsAiBridge::Registry::ContextAggregator::AggregateResult.new(
        results: { 'billing' => 42 }, failures: [], status: :success, elapsed_ms: 1
      )
      output = described_class.new(scalar_result).format
      expect(output).to include('42')
    end
  end

  # ── default_transport_factory ──────────────────────────────────────────────

  describe '.default_transport_factory' do
    let(:canonical_uri) { URI.parse('https://example.com/mcp') }
    let(:transport) { described_class.send(:default_transport_factory, canonical_uri, ['192.0.2.1'], {}) }

    after do
      transport.close
    rescue StandardError
      nil
    end

    it 'builds an MCP HTTP transport bound to the canonical URL via the url keyword' do
      expect(transport).to be_a(MCP::Client::HTTP)
      expect(transport.url.to_s).to eq('https://example.com/mcp')
    end

    it 'applies the configured timeout to the underlying Faraday connection' do
      config.timeout_seconds = 7

      customizer = transport.instance_variable_get(:@faraday_customizer)
      connection = Faraday.new
      customizer.call(connection)

      expect(connection.options.timeout).to eq(7)
      expect(connection.options.open_timeout).to eq(7)
    end
  end

  # ── client construction ────────────────────────────────────────────────────

  describe '.build_client' do
    before do
      config.timeout_seconds = 3.0
      config.max_resolved_addresses = 4
      config.auth_resolver = ->(endpoint, _canonical_uri) { { 'X-Provider' => endpoint } }
      config.allowed_loopback_ports = [3000]
      config.allow_private_networks = true
    end

    it 'propagates timeout and max_resolved_addresses to the policy' do
      client = described_class.send(:build_client, provider)
      policy = client.instance_variable_get(:@policy)

      expect(policy.instance_variable_get(:@timeout_seconds)).to eq(3.0)
      expect(policy.instance_variable_get(:@max_resolved_addresses)).to eq(4)
    end

    it 'caps cleanup_deadline_seconds at the per-tool timeout' do
      client = described_class.send(:build_client, provider)

      expect(client.instance_variable_get(:@timeout_seconds)).to eq(3.0)
      expect(client.instance_variable_get(:@cleanup_deadline_seconds)).to eq(3.0)
    end

    it 'uses 5.0 as the cleanup deadline when the timeout is larger' do
      config.timeout_seconds = 10.0
      client = described_class.send(:build_client, provider)

      expect(client.instance_variable_get(:@cleanup_deadline_seconds)).to eq(5.0)
    end

    it 'passes the auth resolver through to the client' do
      client = described_class.send(:build_client, provider)

      expect(client.instance_variable_get(:@auth_resolver)).to eq(config.auth_resolver)
    end

    it 'sets max_reconnection_wait on the transport factory' do
      client = described_class.send(:build_client, provider)
      factory = client.instance_variable_get(:@transport_factory)

      expect(factory).to be_a(Method)
      transport = factory.call(URI.parse('https://example.com/mcp'), ['192.0.2.1'], {})
      expect(transport.instance_variable_get(:@max_reconnection_wait)).to eq(3.0)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
