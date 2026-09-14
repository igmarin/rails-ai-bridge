# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::HttpStructuredLogChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }

  describe '#call' do
    around do |example|
      saved_mount = RailsAiBridge.configuration.auto_mount
      saved_log = RailsAiBridge.configuration.mcp.http_log_json
      example.run
    ensure
      RailsAiBridge.configuration.auto_mount = saved_mount
      RailsAiBridge.configuration.mcp.http_log_json = saved_log
    end

    context 'when HTTP MCP auto-mount is disabled' do
      it 'returns a pass check' do
        RailsAiBridge.configuration.auto_mount = false
        RailsAiBridge.configuration.mcp.http_log_json = false

        result = checker.call

        expect(result.status).to eq(:pass)
        expect(result.message).to include('not required')
      end
    end

    context 'when HTTP MCP is auto-mounted and structured logs are enabled' do
      it 'returns a pass check' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.mcp.http_log_json = true

        result = checker.call

        expect(result.status).to eq(:pass)
        expect(result.message).to include('http_log_json')
      end
    end

    context 'when HTTP MCP is auto-mounted and structured logs are off' do
      it 'returns a warn check' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.mcp.http_log_json = false

        result = checker.call

        expect(result.status).to eq(:warn)
        expect(result.message).to include('auto-mounted')
        expect(result.fix).to include('http_log_json')
      end
    end
  end
end
