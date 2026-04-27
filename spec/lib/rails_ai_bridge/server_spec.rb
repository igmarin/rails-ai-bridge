# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Server do
  let(:app) { 'TestApp' }
  let(:server) { described_class.new(app, transport: RailsAiBridge::Server::STDIO_TRANSPORT) }
  let(:http_server) { described_class.new(app, transport: RailsAiBridge::Server::HTTP_TRANSPORT) }

  before do
    allow(RailsAiBridge).to receive(:configuration).and_return(
      double(
        server_name: 'Test Server',
        server_version: '1.0.0',
        additional_tools: [],
        http_bind: 'localhost',
        http_port: 3000,
        http_path: '/mcp'
      )
    )
    allow(RailsAiBridge::Resources).to receive_messages(build_resources: [], build_templates: [])
    allow(RailsAiBridge::Resources).to receive(:register)
    allow(RailsAiBridge).to receive(:validate_http_mcp_server_in_production!)
  end

  describe '.initialize' do
    it 'sets app and transport_type' do
      expect(server.app).to eq(app)
      expect(server.transport_type).to eq(RailsAiBridge::Server::STDIO_TRANSPORT)
    end

    it 'defaults transport to :stdio' do
      default_server = described_class.new(app)
      expect(default_server.transport_type).to eq(RailsAiBridge::Server::STDIO_TRANSPORT)
    end
  end

  describe '#tool_classes' do
    it 'returns built-in tools plus additional tools' do
      additional_tools = [double(tool_name: 'custom_tool')]
      allow(RailsAiBridge.configuration).to receive(:additional_tools).and_return(additional_tools)

      tool_classes = server.tool_classes

      expect(tool_classes).to include(*RailsAiBridge::Server::TOOLS)
      expect(tool_classes).to include(*additional_tools)
    end

    it 'returns only built-in tools when no additional tools' do
      allow(RailsAiBridge.configuration).to receive(:additional_tools).and_return([])

      tool_classes = server.tool_classes

      expect(tool_classes).to eq(RailsAiBridge::Server::TOOLS)
    end
  end

  describe '#build' do
    it 'creates MCP server with configuration' do
      allow(MCP::Server).to receive(:new).and_return(double(register: nil))

      server.build

      expect(MCP::Server).to have_received(:new).with(
        name: 'Test Server',
        version: '1.0.0',
        tools: server.tool_classes,
        resources: [],
        resource_templates: []
      )
    end

    it 'registers resources with the server' do
      mcp_server = double
      allow(MCP::Server).to receive(:new).and_return(mcp_server)

      server.build

      expect(RailsAiBridge::Resources).to have_received(:register).with(mcp_server)
    end

    it 'returns the configured server' do
      mcp_server = double
      allow(MCP::Server).to receive(:new).and_return(mcp_server)

      result = server.build

      expect(result).to eq(mcp_server)
    end
  end

  describe '#start' do
    context 'with stdio transport' do
      it 'starts stdio transport' do
        mcp_server = double
        allow(server).to receive(:build).and_return(mcp_server)
        allow(server).to receive(:start_stdio)

        server.start

        expect(server).to have_received(:start_stdio).with(mcp_server)
      end
    end

    context 'with http transport' do
      it 'starts http transport' do
        mcp_server = double
        allow(http_server).to receive(:build).and_return(mcp_server)
        allow(http_server).to receive(:start_http)

        http_server.start

        expect(http_server).to have_received(:start_http).with(mcp_server)
      end
    end

    context 'with streamable_http transport' do
      let(:streamable_server) { described_class.new(app, transport: RailsAiBridge::Server::STREAMABLE_HTTP_TRANSPORT) }

      it 'starts http transport for streamable_http' do
        mcp_server = double
        allow(streamable_server).to receive(:build).and_return(mcp_server)
        allow(streamable_server).to receive(:start_http)

        streamable_server.start

        expect(streamable_server).to have_received(:start_http).with(mcp_server)
      end
    end

    context 'with unknown transport' do
      let(:invalid_server) { described_class.new(app, transport: :invalid) }

      it 'raises ConfigurationError' do
        expect do
          invalid_server.start
        end.to raise_error(RailsAiBridge::ConfigurationError, 'Unknown transport: invalid. Use :stdio, :http, or :streamable_http')
      end
    end
  end

  describe 'private methods (characterization)' do
    describe '#start_stdio' do
      it 'creates stdio transport and opens it' do
        mcp_server = double
        transport = double(open: true)
        allow(MCP::Server::Transports::StdioTransport).to receive(:new).with(mcp_server).and_return(transport)

        expect { server.send(:start_stdio, mcp_server) }.to output(/MCP server started \(stdio transport\)/).to_stderr
        expect(transport).to have_received(:open)
      end

      it 'logs available tools' do
        mcp_server = double
        transport = double(open: true)
        allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(transport)
        allow(RailsAiBridge.configuration).to receive(:additional_tools).and_return([])

        expect { server.send(:start_stdio, mcp_server) }.to output(/Tools: rails_get_schema, rails_get_routes/).to_stderr
      end
    end

    describe '#start_http' do
      before do
        allow(http_server).to receive(:validate_http_server_in_production)
        allow(http_server).to receive_messages(create_http_transport: double, build_rack_app: double)
        allow(http_server).to receive(:log_http_startup)
        allow(http_server).to receive(:run_rack_server)
      end

      it 'validates HTTP server in production' do
        mcp_server = double
        http_server.send(:start_http, mcp_server)

        expect(http_server).to have_received(:validate_http_server_in_production)
      end

      it 'creates HTTP transport' do
        mcp_server = double
        http_server.send(:start_http, mcp_server)

        expect(http_server).to have_received(:create_http_transport).with(mcp_server)
      end

      it 'builds rack app' do
        mcp_server = double
        transport = double
        allow(http_server).to receive(:create_http_transport).and_return(transport)
        http_server.send(:start_http, mcp_server)

        expect(http_server).to have_received(:build_rack_app).with(transport, '/mcp')
      end

      it 'logs startup information' do
        mcp_server = double
        http_server.send(:start_http, mcp_server)

        expect(http_server).to have_received(:log_http_startup)
      end

      it 'runs rack server' do
        mcp_server = double
        transport = double
        rack_app = double
        allow(http_server).to receive_messages(create_http_transport: transport, build_rack_app: rack_app)
        http_server.send(:start_http, mcp_server)

        expect(http_server).to have_received(:run_rack_server).with(rack_app, RailsAiBridge.configuration)
      end
    end

    describe '#run_rack_server' do
      let(:rack_app) { double('rack app') }
      let(:handler) { double('handler', run: true) }

      it 'runs the Rackup handler when rackup is available' do
        allow(http_server).to receive(:require).with('rackup').and_return(true)
        stub_const('Rackup::Handler', double(default: handler))

        http_server.send(:run_rack_server, rack_app, RailsAiBridge.configuration)

        expect(handler).to have_received(:run).with(rack_app, Host: 'localhost', Port: 3000)
      end

      it 'falls back to Rack::Handler when rackup is unavailable' do
        allow(http_server).to receive(:require).with('rackup').and_raise(LoadError)
        allow(http_server).to receive(:require).with('rack/handler').and_return(true)
        stub_const('Rack::Handler', double(default: handler))

        http_server.send(:run_rack_server, rack_app, RailsAiBridge.configuration)

        expect(handler).to have_received(:run).with(rack_app, Host: 'localhost', Port: 3000)
      end
    end

    describe '#build_rack_app' do
      it 'builds HttpTransportApp with transport and path' do
        transport = double
        path = '/mcp'
        app = double
        allow(RailsAiBridge::HttpTransportApp).to receive(:build).with(transport: transport, path: path).and_return(app)

        result = http_server.send(:build_rack_app, transport, path)

        expect(result).to eq(app)
        expect(RailsAiBridge::HttpTransportApp).to have_received(:build).with(transport: transport, path: path)
      end
    end
  end
end
