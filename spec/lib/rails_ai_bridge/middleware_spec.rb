# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/middleware'

RSpec.describe RailsAiBridge::Middleware do
  let(:inner_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:middleware) { described_class.new(inner_app) }

  around do |example|
    saved_token = RailsAiBridge.configuration.http_mcp_token
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
  end

  describe '#call' do
    it 'passes non-MCP requests through to the app' do
      env = Rack::MockRequest.env_for('/users')
      status, _headers, body = middleware.call(env)
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'intercepts requests at the configured MCP path' do
      env = Rack::MockRequest.env_for('/mcp', method: 'POST', input: '{}')
      status, _headers, _body = middleware.call(env)
      # MCP transport will respond (possibly 400/405 for invalid request)
      # but it should NOT be 200 from the inner app
      expect(status).not_to eq(200)
    end

    context 'when http_mcp_token is configured' do
      before { RailsAiBridge.configuration.http_mcp_token = 'secret-mcp' }

      it 'returns 401 without Authorization' do
        env = Rack::MockRequest.env_for('/mcp', method: 'POST', input: '{}')
        status, headers, body = middleware.call(env)
        expect(status).to eq(401)
        expect(headers['Content-Type']).to eq('application/json')
        expect(headers['WWW-Authenticate']).to include('Bearer')
        expect(body.first).to include('Unauthorized')
      end

      it 'returns 401 with wrong Bearer token' do
        env = Rack::MockRequest.env_for(
          '/mcp',
          method: 'POST',
          input: '{}',
          'HTTP_AUTHORIZATION' => 'Bearer wrong'
        )
        status, = middleware.call(env)
        expect(status).to eq(401)
      end

      it 'allows the request through when Bearer matches' do
        fake_transport = instance_double(MCP::Server::Transports::StreamableHTTPTransport)
        allow(fake_transport).to receive(:handle_request).and_return([200, {}, ['OK']])
        mw = described_class.new(inner_app)
        allow(mw).to receive(:transport).and_return(fake_transport)

        env = Rack::MockRequest.env_for(
          '/mcp',
          method: 'POST',
          input: '{}',
          'HTTP_AUTHORIZATION' => 'Bearer secret-mcp'
        )
        status, = mw.call(env)
        expect(status).to eq(200)
        expect(fake_transport).to have_received(:handle_request)
      end
    end
  end
end
