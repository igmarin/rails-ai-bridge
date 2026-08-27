# frozen_string_literal: true

require 'spec_helper'
require 'mcp'
require 'rackup'
require 'resolv'
require 'socket'
require 'webrick'

# Simple MCP tool used by the loopback provider. It returns structured text
# content and advertises itself as read-only and non-destructive so the
# policy safety checks pass.
EchoTool = MCP::Tool.define(
  name: 'echo_test',
  description: 'echoes a message',
  input_schema: {
    type: 'object',
    properties: { 'message' => { type: 'string' } }
  },
  annotations: { read_only_hint: true, destructive_hint: false }
) do |message:|
  MCP::Tool::Response.new([{ type: 'text', text: "ok: #{message}" }])
end

# Resolver that short-circuits DNS and returns a loopback address. This keeps
# the integration self-contained and avoids relying on external DNS.
class FakeResolver
  attr_writer :timeouts

  def getaddresses(_name)
    ['127.0.0.1']
  end
end

RSpec.describe RailsAiBridge::Registry::ContextProviderClient do
  let(:port) do
    tcp = TCPServer.new('127.0.0.1', 0)
    chosen = tcp.addr[1]
    tcp.close
    chosen
  end

  let(:mcp_server) do
    MCP::Server.new(name: 'loopback', version: '1.0.0', tools: [EchoTool])
  end

  let(:transport_app) { MCP::Server::Transports::StreamableHTTPTransport.new(mcp_server) }

  let(:policy) do
    RailsAiBridge::Registry::EndpointPolicy.new(
      resolver: FakeResolver.new,
      allowed_hosts: [],
      allowed_loopback_ports: [port],
      allow_private_networks: false,
      timeout_seconds: 5,
      max_resolved_addresses: 1
    )
  end

  let(:provider) do
    RailsAiBridge::Registry::ContextProviderDefinition.new(
      type: 'mcp',
      endpoint: "http://127.0.0.1:#{port}/mcp",
      optional: false,
      tools: [
        RailsAiBridge::Registry::ContextToolSpec.new(name: 'echo_test', field: nil, arguments: nil)
      ]
    )
  end

  let(:client) do
    described_class.new(
      provider: provider,
      policy: policy,
      transport_factory: method(:build_client),
      auth_resolver: nil,
      timeout_seconds: 5,
      cleanup_deadline_seconds: 2.0
    )
  end

  around do |example|
    server_thread = Thread.new do
      Rackup::Handler::WEBrick.run(
        transport_app,
        Host: '127.0.0.1',
        Port: port,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
    end

    # WEBrick needs a moment to bind and start accepting connections.
    sleep 0.5

    example.run
  ensure
    Rackup::Handler::WEBrick.shutdown
    server_thread&.join(2)
  end

  # @param uri [URI]
  # @param addresses [Array<String>]
  # @param headers [Hash]
  # @return [MCP::Client]
  def build_client(uri, addresses, headers)
    http = MCP::Client::HTTP.new(
      url: uri,
      headers: headers,
      max_reconnection_wait: 5.0
    ) do |faraday|
      faraday.options.timeout = 5.0
      faraday.options.open_timeout = 5.0
      faraday.adapter RailsAiBridge::Registry::PinningHttpAdapter,
                      addresses: addresses,
                      original_host: uri.host
    end

    MCP::Client.new(transport: http)
  end

  describe '#probe' do
    it 'succeeds against a real loopback MCP server' do
      result = client.probe

      expect(result.status).to eq(:success)
      expect(result.error).to be_nil
    end
  end

  describe '#call_tool' do
    it 'calls a real read-only tool and unwraps the JSON-RPC result content' do
      result = client.call_tool('echo_test', arguments: { 'message' => 'hello' })

      expect(result.status).to eq(:success)
      expect(result.content).to eq([{ 'type' => 'text', 'text' => 'ok: hello' }])
    end
  end
end
