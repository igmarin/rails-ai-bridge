# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

# Characterization specs that pin MCP error response behavior and response
# bounds. These cover the HTTP transport's error handling (404, 401, 403,
# 429), the resource read error path, and tool response truncation limits.
#
# These specs pin the current error response shapes so the MCP 1.3.0
# upgrade doesn't silently change status codes, headers, or body formats.
RSpec.describe 'MCP error responses and bounds (SDK 1.3.0)' do
  let(:transport) { instance_double(MCP::Server::Transports::StreamableHTTPTransport) }

  around do |example|
    saved_token = RailsAiBridge.configuration.http_mcp_token
    saved_require_http_auth = RailsAiBridge.configuration.mcp.require_http_auth
    saved_authorize = RailsAiBridge.configuration.mcp.authorize
    saved_rate_limiter = RailsAiBridge.configuration.mcp.rate_limiter
    saved_max_reqs = RailsAiBridge.configuration.mcp.rate_limit_max_requests
    saved_token_resolver = RailsAiBridge.configuration.mcp_token_resolver
    saved_jwt_decoder = RailsAiBridge.configuration.mcp_jwt_decoder
    saved_rate_limit_window = RailsAiBridge.configuration.mcp.rate_limit_window_seconds
    saved_cors_origins = RailsAiBridge.configuration.mcp.cors_origins
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
    RailsAiBridge.configuration.mcp.require_http_auth = saved_require_http_auth
    RailsAiBridge.configuration.mcp.authorize = saved_authorize
    RailsAiBridge.configuration.mcp.rate_limiter = saved_rate_limiter
    RailsAiBridge.configuration.mcp.rate_limit_max_requests = saved_max_reqs
    RailsAiBridge.configuration.mcp_token_resolver = saved_token_resolver
    RailsAiBridge.configuration.mcp_jwt_decoder = saved_jwt_decoder
    RailsAiBridge.configuration.mcp.rate_limit_window_seconds = saved_rate_limit_window
    RailsAiBridge.configuration.mcp.cors_origins = saved_cors_origins
  end

  before do
    RailsAiBridge.configuration.http_mcp_token = nil
    RailsAiBridge.configuration.mcp.require_http_auth = false
    RailsAiBridge.configuration.mcp.authorize = nil
    RailsAiBridge.configuration.mcp.rate_limiter = nil
    RailsAiBridge.configuration.mcp.rate_limit_max_requests = 0
  end

  # ---- 404 Not Found ----

  describe '404 for non-MCP paths' do
    it 'returns 404 with JSON error body' do
      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      status, headers, body = app.call(Rack::MockRequest.env_for('/users'))

      expect(status).to eq(404)
      expect(headers['Content-Type']).to eq('application/json')
      expect(body.first).to include('Not found')
    end

    it 'returns 404 for paths that do not match the MCP endpoint' do
      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      status, = app.call(Rack::MockRequest.env_for('/api/v1/data'))

      expect(status).to eq(404)
    end

    it 'does not delegate to transport for non-MCP paths' do
      allow(transport).to receive(:handle_request).and_return([200, {}, ['OK']])
      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      app.call(Rack::MockRequest.env_for('/users'))

      expect(transport).not_to have_received(:handle_request)
    end
  end

  # ---- 401 Unauthorized ----

  describe '401 when authentication is required but missing' do
    it 'returns 401 when require_http_auth is true and no auth is configured' do
      token_key = RailsAiBridge::Mcp::Authenticator::TOKEN_ENV_KEY
      saved_env_token = ENV.fetch(token_key, nil)
      ENV.delete(token_key)

      begin
        RailsAiBridge.configuration.mcp.require_http_auth = true
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp_token_resolver = nil
        RailsAiBridge.configuration.mcp_jwt_decoder = nil

        app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

        status, headers, = app.call(Rack::MockRequest.env_for('/mcp', method: 'POST'))

        expect(status).to eq(401)
        expect(headers['WWW-Authenticate']).to include('Bearer')
      ensure
        if saved_env_token
          ENV[token_key] = saved_env_token
        else
          ENV.delete(token_key)
        end
      end
    end

    it 'returns 401 when a token is configured but Authorization header is missing' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      status, headers, = app.call(Rack::MockRequest.env_for('/mcp', method: 'POST'))

      expect(status).to eq(401)
      expect(headers['WWW-Authenticate']).to include('Bearer')
    end
  end

  # ---- 403 Forbidden ----

  describe '403 when authorize lambda denies access' do
    it 'returns 403 when authorize returns false' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'
      RailsAiBridge.configuration.mcp.authorize = ->(_ctx, _req) { false }

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      env = Rack::MockRequest.env_for('/mcp', method: 'POST', 'HTTP_AUTHORIZATION' => 'Bearer secret')
      allow(Rails.logger).to receive(:warn)
      status, _headers, body = app.call(env)

      expect(status).to eq(403)
      expect(body.first).to include('Forbidden')
    end

    it 'returns 403 when authorize lambda raises' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'
      RailsAiBridge.configuration.mcp.authorize = ->(_ctx, _req) { raise 'boom' }

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')

      env = Rack::MockRequest.env_for('/mcp', method: 'POST', 'HTTP_AUTHORIZATION' => 'Bearer secret')
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      status, _headers, body = app.call(env)

      expect(status).to eq(403)
      expect(body.first).to include('Forbidden')
    end
  end

  # ---- 429 Too Many Requests ----

  describe '429 when rate limit is exceeded' do
    it 'returns 429 with Retry-After header' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'
      RailsAiBridge.configuration.mcp.rate_limit_max_requests = 1
      RailsAiBridge.configuration.mcp.rate_limit_window_seconds = 60

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')
      allow(transport).to receive(:handle_request).and_return([200, {}, ['OK']])

      env = Rack::MockRequest.env_for('/mcp', method: 'POST',
                                              'HTTP_AUTHORIZATION' => 'Bearer secret', 'REMOTE_ADDR' => '1.2.3.4')
      app.call(env)
      status, headers, body = app.call(env)

      expect(status).to eq(429)
      expect(headers['Retry-After']).to eq('60')
      expect(body.first).to include('Too many requests')
    end

    it 'emits a rate_limit.hit instrumentation event' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'
      RailsAiBridge.configuration.mcp.rate_limiter = ->(_ip) { false }
      RailsAiBridge.configuration.mcp.rate_limit_max_requests = 0

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')
      env = Rack::MockRequest.env_for('/mcp', method: 'POST',
                                              'HTTP_AUTHORIZATION' => 'Bearer secret', 'REMOTE_ADDR' => '1.2.3.4')

      events = []
      callback = ->(name, _started, _finished, _unique_id, payload) { events << [name, payload] }

      ActiveSupport::Notifications.subscribed(callback, 'rails_ai_bridge.rate_limit.hit') do
        app.call(env)
      end

      expect(events.size).to eq(1)
      expect(events.first.last[:ip]).to eq('1.2.3.4')
    end
  end

  # ---- Resource read error ----

  describe 'resource read error for unknown URIs' do
    it 'raises when resource URI is not found' do
      expect do
        RailsAiBridge::Resources.send(:handle_read, uri: 'rails://nonexistent')
      end.to raise_error(RuntimeError, /Unknown resource/)
    end
  end

  # ---- Response bounds: tool truncation ----

  describe 'tool response truncation bounds' do
    context 'when max_tool_response_chars is set' do
      before do
        allow(RailsAiBridge.configuration).to receive(:max_tool_response_chars).and_return(50)
      end

      it 'truncates responses exceeding the limit' do
        long_text = 'x' * 200
        response = RailsAiBridge::Tools::BaseTool.text_response(long_text)

        expect(response.content.first[:text].length).to be <= 50
      end

      it 'includes a truncation notice' do
        response = RailsAiBridge::Tools::BaseTool.text_response('x' * 200)

        expect(response.content.first[:text]).to include('Response truncated')
      end

      it 'does not truncate responses under the limit' do
        response = RailsAiBridge::Tools::BaseTool.text_response('short')

        expect(response.content.first[:text]).to eq('short')
      end
    end

    context 'when max_tool_response_chars is nil' do
      before do
        allow(RailsAiBridge.configuration).to receive(:max_tool_response_chars).and_return(nil)
      end

      it 'returns full text without truncation' do
        text = 'x' * 50_000
        response = RailsAiBridge::Tools::BaseTool.text_response(text)

        expect(response.content.first[:text]).to eq(text)
      end
    end
  end

  # ---- CORS preflight (204) ----

  describe '204 for CORS preflight requests' do
    it 'returns 204 with CORS headers for allowed origins' do
      RailsAiBridge.configuration.mcp.cors_origins = ['https://example.com']
      allow(transport).to receive(:handle_request)

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')
      env = Rack::MockRequest.env_for('/mcp', method: 'OPTIONS', 'HTTP_ORIGIN' => 'https://example.com')

      status, headers, body = app.call(env)

      expect(status).to eq(204)
      expect(headers['Access-Control-Allow-Origin']).to eq('https://example.com')
      expect(body.first).to be_empty
    end

    it 'does not delegate to transport for preflight' do
      RailsAiBridge.configuration.mcp.cors_origins = ['https://example.com']
      allow(transport).to receive(:handle_request)

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')
      app.call(Rack::MockRequest.env_for('/mcp', method: 'OPTIONS', 'HTTP_ORIGIN' => 'https://example.com'))

      expect(transport).not_to have_received(:handle_request)
    end
  end

  # ---- Authorized request delegation ----

  describe 'authorized request delegation to transport' do
    it 'delegates to transport.handle_request for authorized requests' do
      RailsAiBridge.configuration.http_mcp_token = 'secret'
      allow(transport).to receive(:handle_request).and_return([200, {}, ['OK']])

      app = RailsAiBridge::HttpTransportApp.build(transport: transport, path: '/mcp')
      env = Rack::MockRequest.env_for('/mcp', method: 'POST', 'HTTP_AUTHORIZATION' => 'Bearer secret')

      status, = app.call(env)

      expect(status).to eq(200)
      expect(transport).to have_received(:handle_request)
    end
  end
end
