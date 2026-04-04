# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::HttpTransportApp do
  let(:transport) { instance_double(MCP::Server::Transports::StreamableHTTPTransport) }

  around do |example|
    saved_token    = RailsAiBridge.configuration.http_mcp_token
    saved_max_reqs = RailsAiBridge.configuration.mcp.rate_limit_max_requests
    saved_log      = RailsAiBridge.configuration.mcp.http_log_json
    saved_authorize = RailsAiBridge.configuration.mcp.authorize
    saved_require_http_auth = RailsAiBridge.configuration.mcp.require_http_auth
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
    RailsAiBridge.configuration.mcp.rate_limit_max_requests = saved_max_reqs
    RailsAiBridge.configuration.mcp.http_log_json = saved_log
    RailsAiBridge.configuration.mcp.authorize = saved_authorize
    RailsAiBridge.configuration.mcp.require_http_auth = saved_require_http_auth
  end

  describe ".build" do
    it "returns 404 for non-MCP paths" do
      app = described_class.build(transport: transport, path: "/mcp")

      status, headers, body = app.call(Rack::MockRequest.env_for("/users"))

      expect(status).to eq(404)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(body.first).to include("Not found")
    end

    it "returns 401 when require_http_auth is true and no auth strategy is configured" do
      token_key = RailsAiBridge::Mcp::Authenticator::TOKEN_ENV_KEY
      saved_env_token = ENV[token_key]
      ENV.delete(token_key)

      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp_token_resolver = nil
      RailsAiBridge.configuration.mcp_jwt_decoder = nil
      RailsAiBridge.configuration.mcp.require_http_auth = true
      app = described_class.build(transport: transport, path: "/mcp")

      status, headers, = app.call(Rack::MockRequest.env_for("/mcp", method: "POST"))

      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to include("Bearer")
    ensure
      if saved_env_token
        ENV[token_key] = saved_env_token
      else
        ENV.delete(token_key)
      end
    end

    it "returns 401 when auth is configured and Authorization is missing" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      app = described_class.build(transport: transport, path: "/mcp")

      status, headers, = app.call(Rack::MockRequest.env_for("/mcp", method: "POST"))

      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to include("Bearer")
    end

    it "delegates to the transport for authorized requests" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      app = described_class.build(transport: transport, path: "/mcp")

      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      )

      status, = app.call(env)

      expect(status).to eq(200)
      expect(transport).to have_received(:handle_request)
    end

    it "returns 429 and Retry-After when rate limit is exceeded" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.rate_limit_max_requests = 1
      RailsAiBridge.configuration.mcp.rate_limit_window_seconds = 60
      app = described_class.build(transport: transport, path: "/mcp")

      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret",
        "REMOTE_ADDR" => "1.2.3.4"
      )

      allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      app.call(env)
      status, headers, body = app.call(env)

      expect(status).to eq(429)
      expect(headers["Retry-After"]).to eq("60")
      expect(body.first).to include("Too many requests")
    end

    it "returns 403 when authorize lambda returns falsey" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.authorize = ->(_ctx, _req) { false }
      app = described_class.build(transport: transport, path: "/mcp")

      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      )

      status, _headers, body = app.call(env)

      expect(status).to eq(403)
      expect(body.first).to include("Forbidden")
    end

    it "returns 403 when authorize lambda raises" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.authorize = ->(_ctx, _req) { raise "boom" }
      app = described_class.build(transport: transport, path: "/mcp")

      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      )

      allow(Rails.logger).to receive(:error)
      status, _headers, body = app.call(env)

      expect(status).to eq(403)
      expect(body.first).to include("Forbidden")
      expect(Rails.logger).to have_received(:error).with(/authorize lambda raised/)
    end

    it "emits a structured log when http_log_json is enabled" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.http_log_json = true
      allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      app = described_class.build(transport: transport, path: "/mcp")

      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      )

      expect(Rails.logger).to receive(:info).at_least(:once)
      app.call(env)
    end
  end
end
