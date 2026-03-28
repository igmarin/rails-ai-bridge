# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::HttpTransportApp do
  let(:transport) { instance_double(MCP::Server::Transports::StreamableHTTPTransport) }

  around do |example|
    saved_token = RailsAiBridge.configuration.http_mcp_token
    saved_authz = RailsAiBridge.configuration.mcp.authorize
    saved_rl_max = RailsAiBridge.configuration.mcp.rate_limit_max_requests
    saved_rl_win = RailsAiBridge.configuration.mcp.rate_limit_window_seconds
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
    RailsAiBridge.configuration.mcp.authorize = saved_authz
    RailsAiBridge.configuration.mcp.rate_limit_max_requests = saved_rl_max
    RailsAiBridge.configuration.mcp.rate_limit_window_seconds = saved_rl_win
  end

  describe ".build" do
    it "returns 404 for non-MCP paths" do
      app = described_class.build(transport: transport, path: "/mcp")

      status, headers, body = app.call(Rack::MockRequest.env_for("/users"))

      expect(status).to eq(404)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(body.first).to include("Not found")
    end

    it "returns 401 when auth is configured and Authorization is missing" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      app = described_class.build(transport: transport, path: "/mcp")

      status, headers, = app.call(Rack::MockRequest.env_for("/mcp", method: "POST"))

      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to include("Bearer")
    end

    it "returns 429 when rate limit is exceeded before auth" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.rate_limit_max_requests = 2
      RailsAiBridge.configuration.mcp.rate_limit_window_seconds = 60
      allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      app = described_class.build(transport: transport, path: "/mcp")

      base_env = {
        "REMOTE_ADDR" => "203.0.113.9",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      }

      expect(app.call(Rack::MockRequest.env_for("/mcp", **base_env)).first).to eq(200)
      expect(app.call(Rack::MockRequest.env_for("/mcp", **base_env)).first).to eq(200)

      status, headers, body = app.call(Rack::MockRequest.env_for("/mcp", **base_env))

      expect(status).to eq(429)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(headers["Retry-After"]).to eq("60")
      expect(body.first).to include("Too Many Requests")
      expect(transport).to have_received(:handle_request).twice
    end

    it "uses a 60s Retry-After when rate_limit_window_seconds is not positive" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.rate_limit_max_requests = 1
      RailsAiBridge.configuration.mcp.rate_limit_window_seconds = 0
      allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      app = described_class.build(transport: transport, path: "/mcp")

      env = {
        "REMOTE_ADDR" => "198.51.100.2",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer secret"
      }
      expect(app.call(Rack::MockRequest.env_for("/mcp", **env)).first).to eq(200)

      _status, headers, = app.call(Rack::MockRequest.env_for("/mcp", **env))

      expect(headers["Retry-After"]).to eq("60")
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

    context "when config.mcp.authorize is set" do
      before do
        RailsAiBridge.configuration.http_mcp_token = "secret"
      end

      it "returns 403 when authorize rejects the context" do
        RailsAiBridge.configuration.mcp.authorize = ->(_ctx, _req) { false }
        allow(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
        app = described_class.build(transport: transport, path: "/mcp")

        env = Rack::MockRequest.env_for(
          "/mcp",
          method: "POST",
          "HTTP_AUTHORIZATION" => "Bearer secret"
        )
        status, headers, body = app.call(env)

        expect(status).to eq(403)
        expect(headers["Content-Type"]).to eq("application/json")
        expect(body.first).to include("Forbidden")
        expect(transport).not_to have_received(:handle_request)
      end

      it "delegates when authorize accepts" do
        RailsAiBridge.configuration.mcp.authorize = ->(ctx, _req) { ctx == :static_bearer }
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
    end
  end
end
