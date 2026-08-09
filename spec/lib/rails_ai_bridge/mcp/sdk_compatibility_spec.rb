# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

RSpec.describe 'MCP Ruby SDK compatibility (1.x)' do
  describe 'SDK version' do
    it 'loads mcp 1.x' do
      version = Gem.loaded_specs['mcp']&.version || Gem::Version.new(MCP::VERSION)
      expect(version).to be >= Gem::Version.new('1.0.0')
      expect(version).to be < Gem::Version.new('2.0.0')
    end
  end

  describe 'tool surface used by rails-ai-bridge' do
    it 'exposes MCP::Tool with tool_name / input_schema / annotations' do
      expect(MCP::Tool).to respond_to(:tool_name)
      expect(MCP::Tool).to respond_to(:input_schema)
      expect(MCP::Tool).to respond_to(:annotations)
    end

    it 'builds MCP::Tool::Response text payloads' do
      response = MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])
      expect(response).to respond_to(:to_h)
      hash = response.to_h
      expect(hash).to be_a(Hash)
    end
  end

  describe 'server and transport surface' do
    it 'constructs MCP::Server with tools' do
      server = MCP::Server.new(
        name: 'rails-ai-bridge-compat',
        version: '0.0.0',
        tools: []
      )
      expect(server).to be_a(MCP::Server)
    end

    it 'exposes StreamableHTTPTransport and StdioTransport' do
      expect(defined?(MCP::Server::Transports::StreamableHTTPTransport)).to eq('constant')
      expect(defined?(MCP::Server::Transports::StdioTransport)).to eq('constant')
    end
  end

  describe 'built-in tool inheritance' do
    it 'registers BaseTool as an MCP::Tool subclass' do
      expect(RailsAiBridge::Tools::BaseTool.ancestors).to include(MCP::Tool)
    end

    it 'invokes a built-in tool and returns an MCP::Tool::Response' do
      response = RailsAiBridge::Tools::GetTestInfo.call
      expect(response).to be_a(MCP::Tool::Response)
    end
  end
end
