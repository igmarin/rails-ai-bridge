# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::HttpTransportApp do
  let(:transport) { instance_double(MCP::Server::Transports::StreamableHTTPTransport) }

  around do |example|
    saved_token = RailsAiBridge.configuration.http_mcp_token
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
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
  end
end
