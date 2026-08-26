# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

# Characterization specs that pin the MCP protocol behavior as exposed
# through the rails-ai-bridge Server class with the official Ruby MCP SDK.
#
# Current SDK: mcp 1.3.0 (gemspec constraint: >= 1.0, < 2.0)
# Target: tighten to >= 1.3, < 2.0 (age-gated until Aug 29)
#
# These specs pin:
#   - MCP::Server constructor signature and kwargs
#   - Transport class availability and construction
#   - Protocol version advertised by the SDK
#   - The 2026-07-28 stateless lifecycle support
RSpec.describe 'MCP protocol characterization (SDK 1.3.0)' do
  let(:app) { 'TestApp' }
  let(:server) { RailsAiBridge::Server.new(app, transport: RailsAiBridge::Server::STDIO_TRANSPORT) }

  before do
    allow(RailsAiBridge).to receive(:configuration).and_return(
      double(
        server_name: 'Test Server',
        server_version: '1.0.0',
        additional_tools: [],
        http_bind: 'localhost',
        http_port: 3000,
        http_path: '/mcp',
        mcp: double(tool_result_cache_ttl: 0)
      )
    )
    allow(RailsAiBridge::Resources).to receive_messages(build_resources: [], build_templates: [])
    allow(RailsAiBridge::Resources).to receive(:register)
  end

  # ---- SDK version ----

  describe 'SDK version' do
    it 'is 1.3.0' do
      expect(MCP::VERSION).to eq('1.3.0')
    end

    it 'is within the 1.x stable range' do
      version = Gem.loaded_specs['mcp']&.version || Gem::Version.new(MCP::VERSION)
      expect(version).to be >= Gem::Version.new('1.0.0')
      expect(version).to be < Gem::Version.new('2.0.0')
    end
  end

  # ---- Server construction ----

  describe 'MCP::Server constructor kwargs' do
    it 'accepts name, version, tools, resources, and resource_templates' do
      mcp_server = nil
      allow(MCP::Server).to receive(:new) do |**kwargs|
        mcp_server = double('MCP::Server', kwargs: kwargs)
        mcp_server
      end

      server.build

      expect(MCP::Server).to have_received(:new) do |**kwargs|
        expect(kwargs[:name]).to eq('Test Server')
        expect(kwargs[:version]).to eq('1.0.0')
        expect(kwargs[:tools]).to be_an(Array)
        expect(kwargs[:resources]).to eq([])
        expect(kwargs[:resource_templates]).to eq([])
      end
    end

    it 'passes tool classes wrapped with Instrumentation::InstrumentedTool' do
      allow(MCP::Server).to receive(:new).and_return(double(register: nil))

      server.build

      expect(MCP::Server).to have_received(:new) do |**kwargs|
        kwargs[:tools].each do |tool|
          expect(tool).to be_a(RailsAiBridge::Instrumentation::InstrumentedTool)
        end
      end
    end
  end

  # ---- Transport classes ----

  describe 'transport class availability' do
    it 'exposes StdioTransport' do
      expect(defined?(MCP::Server::Transports::StdioTransport)).to eq('constant')
    end

    it 'exposes StreamableHTTPTransport' do
      expect(defined?(MCP::Server::Transports::StreamableHTTPTransport)).to eq('constant')
    end

    it 'constructs StdioTransport with a server argument' do
      mcp_server = double('MCP::Server')
      transport = double('transport', open: true)
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).with(mcp_server).and_return(transport)

      server.send(:start_stdio, mcp_server)

      expect(MCP::Server::Transports::StdioTransport).to have_received(:new).with(mcp_server)
    end

    it 'constructs StreamableHTTPTransport with a server argument' do
      http_server = RailsAiBridge::Server.new(app, transport: RailsAiBridge::Server::HTTP_TRANSPORT)
      mcp_server = double('MCP::Server')
      transport = double('transport')
      allow(MCP::Server::Transports::StreamableHTTPTransport).to receive(:new).with(mcp_server).and_return(transport)
      allow(http_server).to receive_messages(validate_http_server_in_production: nil, build_rack_app: double,
                                             log_http_startup: nil, run_rack_server: nil)
      allow(RailsAiBridge::Mcp::Authenticator).to receive(:any_configured?).and_return(true)

      http_server.send(:start_http, mcp_server)

      expect(MCP::Server::Transports::StreamableHTTPTransport).to have_received(:new).with(mcp_server)
    end
  end

  # ---- Transport type routing ----

  describe 'transport type routing' do
    it 'routes :stdio to start_stdio' do
      allow(server).to receive(:build).and_return(double('server'))
      allow(server).to receive(:start_stdio)

      server.start

      expect(server).to have_received(:start_stdio)
    end

    it 'routes :http to start_http' do
      http_server = RailsAiBridge::Server.new(app, transport: RailsAiBridge::Server::HTTP_TRANSPORT)
      allow(http_server).to receive(:build).and_return(double('server'))
      allow(http_server).to receive(:start_http)

      http_server.start

      expect(http_server).to have_received(:start_http)
    end

    it 'routes :streamable_http to start_http' do
      streamable = RailsAiBridge::Server.new(app, transport: RailsAiBridge::Server::STREAMABLE_HTTP_TRANSPORT)
      allow(streamable).to receive(:build).and_return(double('server'))
      allow(streamable).to receive(:start_http)

      streamable.start

      expect(streamable).to have_received(:start_http)
    end

    it 'raises ConfigurationError for unknown transport' do
      invalid = RailsAiBridge::Server.new(app, transport: :invalid)

      expect { invalid.start }.to raise_error(RailsAiBridge::ConfigurationError, /Unknown transport: invalid/)
    end
  end

  # ---- 2026-07-28 stateless lifecycle ----

  describe '2026-07-28 stateless lifecycle support' do
    it 'MCP::Server supports resources_read_handler for resource reads' do
      expect(MCP::Server.instance_methods).to include(:resources_read_handler)
    end

    it 'MCP::Server supports resources_list_handler (added in 1.3.0)' do
      expect(MCP::Server.instance_methods).to include(:resources_list_handler)
    end

    it 'MCP::Server supports resources_subscribe_handler' do
      expect(MCP::Server.instance_methods).to include(:resources_subscribe_handler)
    end

    it 'MCP::Server supports resources_unsubscribe_handler' do
      expect(MCP::Server.instance_methods).to include(:resources_unsubscribe_handler)
    end

    it 'MCP::Server supports server_context for handler state' do
      expect(MCP::Server.instance_methods).to include(:server_context)
    end

    it 'MCP::Server supports request_state_security (SEP-2575)' do
      expect(MCP::Server.instance_methods).to include(:request_state_security)
    end

    it 'StreamableHTTPTransport supports handle_request for stateless HTTP' do
      expect(MCP::Server::Transports::StreamableHTTPTransport.instance_methods).to include(:handle_request)
    end

    it 'StreamableHTTPTransport supports serves_subscriptions_listen? (SEP-2575)' do
      expect(MCP::Server::Transports::StreamableHTTPTransport.instance_methods)
        .to include(:serves_subscriptions_listen?)
    end
  end

  # ---- Stdio startup logging ----

  describe 'stdio transport startup' do
    it 'logs startup message to stderr' do
      mcp_server = double('MCP::Server')
      transport = double('transport', open: true)
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(transport)

      expect { server.send(:start_stdio, mcp_server) }.to output(/MCP server started \(stdio transport\)/).to_stderr
    end

    it 'logs tool names to stderr' do
      mcp_server = double('MCP::Server')
      transport = double('transport', open: true)
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(transport)

      expect { server.send(:start_stdio, mcp_server) }.to output(/Tools: rails_get_schema/).to_stderr
    end

    it 'opens the transport' do
      mcp_server = double('MCP::Server')
      transport = double('transport', open: true)
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(transport)

      server.send(:start_stdio, mcp_server)

      expect(transport).to have_received(:open)
    end
  end

  # ---- HTTP transport auth warning ----

  describe 'HTTP transport auth warning' do
    let(:http_server) { RailsAiBridge::Server.new(app, transport: RailsAiBridge::Server::HTTP_TRANSPORT) }

    before do
      allow(http_server).to receive_messages(validate_http_server_in_production: nil,
                                             create_http_transport: double, build_rack_app: double,
                                             log_http_startup: nil, run_rack_server: nil)
    end

    it 'warns when HTTP MCP starts without authentication in non-production' do
      allow(Rails.env).to receive(:production?).and_return(false)
      allow(RailsAiBridge::Mcp::Authenticator).to receive(:any_configured?).and_return(false)

      expect { http_server.send(:start_http, double) }
        .to output(/WARNING: HTTP MCP is running without authentication/).to_stderr
    end

    it 'does not warn when auth is configured' do
      allow(Rails.env).to receive(:production?).and_return(false)
      allow(RailsAiBridge::Mcp::Authenticator).to receive(:any_configured?).and_return(true)

      expect { http_server.send(:start_http, double) }.not_to output(/WARNING/).to_stderr
    end

    it 'does not warn in production' do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(RailsAiBridge::Mcp::Authenticator).to receive(:any_configured?).and_return(false)

      expect { http_server.send(:start_http, double) }.not_to output(/WARNING/).to_stderr
    end
  end

  # ---- Tool count ----

  describe 'built-in tool registration' do
    it 'registers exactly 20 built-in tools' do
      expect(RailsAiBridge::Server::TOOLS.length).to eq(20)
    end

    it 'all tool names are prefixed with rails_' do
      allow(RailsAiBridge.configuration).to receive(:additional_tools).and_return([])

      server.tool_classes.each do |tool|
        expect(tool.tool_name).to start_with('rails_')
      end
    end
  end
end
