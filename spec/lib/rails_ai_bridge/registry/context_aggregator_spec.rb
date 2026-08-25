# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ContextAggregator do
  let(:config) do
    RailsAiBridge::Config::ContextProviders.new.tap do |c|
      c.enabled = true
      c.allowed_hosts = ['example.com']
    end
  end

  let(:scope) { RailsAiBridge::Registry::ProviderRequestScope.new }
  let(:manifest) { instance_double(RailsAiBridge::Registry::RegistryManifest) }
  let(:provider) { build_provider(tools: [simple_tool]) }
  let(:client_factory) { ->(_p) { success_client } }
  let(:aggregator) { described_class.new(manifest:, config:, client_factory:, scope:) }

  before { allow(manifest).to receive(:context_providers).and_return({ 'billing' => provider }) }

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

  def aggregator_with(factory)
    described_class.new(manifest:, config:, client_factory: factory, scope:)
  end

  describe '#fetch_one' do
    it 'fetches a simple tool and returns the result keyed by tool name' do
      result = aggregator.fetch_one('billing')

      expect(result).to be_success
      expect(result.results).to eq({ 'get_status' => { 'status' => 'ok' } })
    end

    it 'fetches a mapped tool and stores the result under the declared field' do
      allow(manifest).to receive(:context_providers)
        .and_return({ 'billing' => build_provider(tools: [mapped_tool]) })

      mapped_client = success_client(success_result([{ 'id' => 1 }]))
      agg = aggregator_with(->(_p) { mapped_client })

      result = agg.fetch_one('billing')

      expect(result).to be_success
      expect(result.results).to eq({ 'invoices' => [{ 'id' => 1 }] })
      expect(mapped_client).to have_received(:call_tool).with('get_invoice', arguments: { 'limit' => 5 })
    end

    it 'raises ArgumentError for an unknown provider' do
      expect { aggregator.fetch_one('unknown') }.to raise_error(ArgumentError, /unknown provider: unknown/)
    end

    it 'returns an error result when a required provider fails' do
      agg = aggregator_with(->(_p) { failing_client })

      result = agg.fetch_one('billing')

      expect(result).to be_error
      expect(result.failures).not_to be_empty
      expect(result.failures.first).to be_a(RailsAiBridge::Registry::ConnectionError)
    end
  end

  describe '#fetch_all' do
    it 'iterates all providers and returns an aggregate result' do
      allow(manifest).to receive(:context_providers)
        .and_return({ 'billing' => provider,
                      'inventory' => build_provider(endpoint: 'https://example.com/mcp2', tools: [simple_tool]) })

      result = aggregator.fetch_all

      expect(result).to be_success
      expect(result.results.keys).to contain_exactly('billing', 'inventory')
    end

    it 'returns success with empty results for an empty manifest' do
      allow(manifest).to receive(:context_providers).and_return({})

      result = aggregator.fetch_all

      expect(result).to be_success
      expect(result.results).to eq({})
      expect(result.failures).to eq([])
    end

    it 'records a partial_failure when an optional provider fails but others succeed' do
      allow(manifest).to receive(:context_providers).and_return(
        'required' => build_provider(endpoint: 'https://required.example.com/mcp', tools: [simple_tool]),
        'optional' => build_provider(endpoint: 'https://optional.example.com/mcp', optional: true, tools: [simple_tool])
      )

      call_count = 0
      factory = lambda do |_p|
        call_count += 1
        if call_count == 1
          success_client
        else
          instance_double(
            RailsAiBridge::Registry::ContextProviderClient, call_tool: error_result
          )
        end
      end
      agg = aggregator_with(factory)

      result = agg.fetch_all

      expect(result).to be_partial_failure
      expect(result.results).to have_key('required')
      expect(result.results).not_to have_key('optional')
      expect(result.failures).not_to be_empty
    end

    it 'returns an error status when a required provider fails' do
      allow(manifest).to receive(:context_providers)
        .and_return({ 'required' => build_provider(endpoint: 'https://required.example.com/mcp', tools: [simple_tool]) })

      agg = aggregator_with(->(_p) { failing_client })

      result = agg.fetch_all

      expect(result).to be_error
      expect(result.failures.first).to be_a(RailsAiBridge::Registry::ConnectionError)
    end

    it 'iterates providers in deterministic order' do
      allow(manifest).to receive(:context_providers).and_return(
        { 'c' => build_provider(endpoint: 'https://c.example.com/mcp', tools: [simple_tool]),
          'a' => build_provider(endpoint: 'https://a.example.com/mcp', tools: [simple_tool]),
          'b' => build_provider(endpoint: 'https://b.example.com/mcp', tools: [simple_tool]) }
      )

      call_order = []
      factory = lambda do |p|
        call_order << p.endpoint
        success_client
      end
      aggregator_with(factory).fetch_all

      expect(call_order).to eq(%w[https://c.example.com/mcp https://a.example.com/mcp https://b.example.com/mcp])
    end
  end

  describe 'request-level memoization' do
    it 'does not call the client twice for the same provider+tool within one scope' do
      call_count = 0
      factory = lambda do |_p|
        call_count += 1
        success_client
      end
      agg = aggregator_with(factory)

      agg.fetch_one('billing')
      agg.fetch_one('billing')

      expect(call_count).to eq(2)
    end
  end

  describe 'count caps' do
    it 'enforces max_providers cap' do
      config.max_providers = 1
      allow(manifest).to receive(:context_providers)
        .and_return({ 'billing' => provider,
                      'inventory' => build_provider(endpoint: 'https://b.example.com/mcp', tools: [simple_tool]) })

      result = aggregator.fetch_all

      expect(result.results.keys).to eq(['billing'])
    end

    it 'enforces max_tools_per_provider cap' do
      config.max_tools_per_provider = 1
      multi = build_provider(
        tools: [
          RailsAiBridge::Registry::ContextToolSpec.new(name: 'tool_a', field: nil, arguments: nil),
          RailsAiBridge::Registry::ContextToolSpec.new(name: 'tool_b', field: nil, arguments: nil)
        ]
      )
      allow(manifest).to receive(:context_providers).and_return({ 'billing' => multi })

      result = aggregator.fetch_one('billing')

      expect(result.results.keys).to eq(['tool_a'])
    end
  end

  describe 'mapping collision detection' do
    it 'rejects two tools mapping to the same field before any network calls' do
      colliding = build_provider(
        tools: [
          RailsAiBridge::Registry::ContextToolSpec.new(name: 'tool_a', field: 'data', arguments: nil),
          RailsAiBridge::Registry::ContextToolSpec.new(name: 'tool_b', field: 'data', arguments: nil)
        ]
      )
      allow(manifest).to receive(:context_providers).and_return({ 'billing' => colliding })

      expect { aggregator.fetch_one('billing') }.to raise_error(
        RailsAiBridge::ConfigurationError, /mapping collision/
      )
    end
  end

  describe 'aggregation budget' do
    it 'stops fetching when the total budget is exceeded' do
      config.aggregation_budget_seconds = 0.1
      allow(manifest).to receive(:context_providers).and_return(
        'a' => build_provider(endpoint: 'https://a.example.com/mcp', tools: [simple_tool]),
        'b' => build_provider(endpoint: 'https://b.example.com/mcp', tools: [simple_tool])
      )

      slow_client = instance_double(
        RailsAiBridge::Registry::ContextProviderClient,
        call_tool: nil
      )
      allow(slow_client).to receive(:call_tool) do
        sleep(0.15)
        success_result
      end
      slow_factory = ->(_p) { slow_client }
      agg = aggregator_with(slow_factory)

      result = agg.fetch_all

      # 0.15s for provider 'a' leaves ~0.05s — not enough for another 0.15s call.
      # Provider 'b' is skipped due to budget exhaustion.
      expect(result.results.keys).to eq(['a'])
    end
  end
end
