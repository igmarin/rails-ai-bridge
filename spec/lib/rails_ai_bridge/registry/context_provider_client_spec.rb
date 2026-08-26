# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ContextProviderClient do
  subject(:client) do
    described_class.new(
      provider: provider,
      policy: policy,
      transport_factory: transport_factory,
      auth_resolver: nil
    )
  end

  let(:policy) { instance_double(RailsAiBridge::Registry::EndpointPolicy) }
  let(:transport_factory) { instance_double(Proc) }
  let(:provider) do
    RailsAiBridge::Registry::ContextProviderDefinition.new(
      type: 'mcp',
      endpoint: 'https://example.com/mcp',
      optional: false,
      tools: [
        RailsAiBridge::Registry::ContextToolSpec.new(name: 'get_status', field: nil, arguments: nil)
      ]
    )
  end

  describe '#call_tool' do
    let(:fake_transport) { double('transport', close: nil) }

    before do
      allow(transport_factory).to receive(:call).and_return(fake_transport)
      allow(policy).to receive(:call).with('https://example.com/mcp').and_return(
        RailsAiBridge::Registry::EndpointPolicy::Result.new(
          success: true,
          error: nil,
          uri: URI.parse('https://example.com/mcp'),
          addresses: ['192.0.2.1']
        )
      )
    end

    it 'returns a connection error when the endpoint policy raises' do
      allow(policy).to receive(:call).with('https://example.com/mcp').and_raise(StandardError, 'policy crashed')

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::ConnectionError)
      expect(transport_factory).not_to have_received(:call)
    end

    it 'returns an error result when the endpoint policy rejects the URL' do
      allow(policy).to receive(:call).with('https://example.com/mcp').and_return(
        RailsAiBridge::Registry::EndpointPolicy::Result.new(
          success: false,
          error: RailsAiBridge::Registry::PolicyError.new('host is not in the allowlist'),
          uri: nil,
          addresses: nil
        )
      )

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(transport_factory).not_to have_received(:call)
    end

    it 'returns a remote tool error when the tool is not safe' do
      fake_tool = double('tool', name: 'get_status', read_only_hint: false, destructive_hint: true)
      allow(fake_transport).to receive(:tools).and_return([fake_tool])

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::RemoteToolError)
      expect(fake_transport).to have_received(:close)
    end

    it 'returns a connection error when the transport fails and closes the transport' do
      allow(fake_transport).to receive(:tools).and_raise(StandardError, 'network timeout')

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::ConnectionError)
      expect(result.error.message).to start_with('provider call failed (StandardError)')
      expect(fake_transport).to have_received(:close)
    end

    it 'returns a timeout error when the transport raises Timeout::Error' do
      allow(fake_transport).to receive(:tools).and_raise(Timeout::Error, 'read timeout')

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::TimeoutError)
      expect(result.error.message).to eq('provider call timed out')
      expect(fake_transport).to have_received(:close)
    end

    it 'returns an authentication error when the auth resolver fails' do
      client = described_class.new(
        provider: provider,
        policy: policy,
        transport_factory: transport_factory,
        auth_resolver: ->(_endpoint, _uri) { raise StandardError, 'auth failed' }
      )

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::AuthenticationError)
      expect(result.error.message).to start_with('authentication resolution failed (StandardError)')
      expect(transport_factory).not_to have_received(:call)
    end

    it 'passes resolved auth headers to the transport factory' do
      auth_resolver = ->(_endpoint, _uri) { { 'Authorization' => 'Bearer token' } }
      client = described_class.new(
        provider: provider,
        policy: policy,
        transport_factory: transport_factory,
        auth_resolver: auth_resolver
      )
      fake_tool = double('tool', name: 'get_status', read_only_hint: true, destructive_hint: false)
      allow(fake_transport).to receive_messages(tools: [fake_tool], call_tool: {})

      client.call_tool('get_status', arguments: {})

      expect(transport_factory).to have_received(:call).with(
        URI.parse('https://example.com/mcp'),
        ['192.0.2.1'],
        { 'Authorization' => 'Bearer token' }
      )
    end

    it 'still returns the original result when transport close raises' do
      fake_tool = double('tool', name: 'get_status', read_only_hint: true, destructive_hint: false)
      allow(fake_transport).to receive_messages(tools: [fake_tool], call_tool: { 'status' => 'ok' })
      allow(fake_transport).to receive(:close).and_raise(StandardError, 'close failed')

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:success)
      expect(result.content).to eq({ 'status' => 'ok' })
    end

    it 'rejects a read-only tool that is not declared in the provider manifest' do
      fake_tool = double('tool', name: 'undeclared_tool', read_only_hint: true, destructive_hint: false)
      allow(fake_transport).to receive_messages(tools: [fake_tool], call_tool: { 'status' => 'ok' })

      result = client.call_tool('undeclared_tool', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::RemoteToolError)
      expect(result.error.message).to include('undeclared_tool')
      expect(transport_factory).not_to have_received(:call)
    end

    it 'calls the remote tool and returns a success result' do
      fake_tool = double('tool', name: 'get_status', read_only_hint: true, destructive_hint: false)
      allow(fake_transport).to receive(:tools).and_return([fake_tool])
      allow(fake_transport).to receive(:call_tool).with(name: 'get_status', arguments: { 'limit' => 1 }).and_return(
        { 'status' => 'ok' }
      )

      result = client.call_tool('get_status', arguments: { 'limit' => 1 })

      expect(result.status).to eq(:success)
      expect(result.content).to eq({ 'status' => 'ok' })
      expect(result.provenance).to eq('https://example.com')
      expect(transport_factory).to have_received(:call).with(
        URI.parse('https://example.com/mcp'),
        ['192.0.2.1'],
        {}
      )
      expect(fake_transport).to have_received(:close)
    end
  end

  describe '#probe' do
    let(:fake_transport) { double('transport', close: nil, tools: []) }

    before do
      allow(transport_factory).to receive(:call).and_return(fake_transport)
      allow(policy).to receive(:call).with('https://example.com/mcp').and_return(
        RailsAiBridge::Registry::EndpointPolicy::Result.new(
          success: true,
          error: nil,
          uri: URI.parse('https://example.com/mcp'),
          addresses: ['192.0.2.1']
        )
      )
    end

    it 'returns a success result when the endpoint is reachable' do
      result = client.probe

      expect(result.status).to eq(:success)
      expect(fake_transport).to have_received(:close)
    end

    it 'returns an error result when the policy rejects the endpoint' do
      allow(policy).to receive(:call).with('https://example.com/mcp').and_return(
        RailsAiBridge::Registry::EndpointPolicy::Result.new(
          success: false,
          error: RailsAiBridge::Registry::PolicyError.new('host not allowed'),
          uri: nil,
          addresses: nil
        )
      )

      result = client.probe

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(transport_factory).not_to have_received(:call)
    end

    it 'returns a connection error when the transport fails and closes the transport' do
      allow(fake_transport).to receive(:tools).and_raise(StandardError, 'connection refused')

      result = client.probe

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::ConnectionError)
      expect(result.error.message).to include('connection refused')
      expect(fake_transport).to have_received(:close)
    end

    it 'returns a timeout error when the transport times out' do
      allow(fake_transport).to receive(:tools).and_raise(Timeout::Error)

      result = client.probe

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::TimeoutError)
      expect(fake_transport).to have_received(:close)
    end

    it 'enforces a timeout on the tools request' do
      allow(fake_transport).to receive(:tools) do
        sleep 0.5
        []
      end

      result = client.probe(timeout: 0.01)

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::TimeoutError)
      expect(fake_transport).to have_received(:close)
    end

    it 'redacts URLs and paths from error messages' do
      allow(fake_transport).to receive(:tools)
        .and_raise(StandardError, 'connection to https://secret.example.com/path?token=abc failed at /etc/secrets/config.yml')

      result = client.probe

      expect(result.status).to eq(:error)
      expect(result.error.message).not_to include('secret.example.com')
      expect(result.error.message).not_to include('token=abc')
      expect(result.error.message).not_to include('/etc/secrets')
      expect(result.error.message).to include('[redacted]')
    end
  end
end
