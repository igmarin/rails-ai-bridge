# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Server do
  let(:server) { described_class.new(Rails.application, transport: :http) }

  around do |example|
    saved = RailsAiBridge.configuration.http_mcp_token
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved
  end

  describe "Rack app from #build_rack_app" do
    it "returns 401 when token is set and Authorization is missing" do
      transport = instance_double(MCP::Server::Transports::StreamableHTTPTransport)
      RailsAiBridge.configuration.http_mcp_token = "rack-secret"
      rack_app = server.send(:build_rack_app, transport, "/mcp")
      env = Rack::MockRequest.env_for("/mcp", method: "POST")
      status, headers, = rack_app.call(env)
      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to include("Bearer")
    end

    it "delegates to the transport when Bearer matches" do
      transport = instance_double(MCP::Server::Transports::StreamableHTTPTransport)
      RailsAiBridge.configuration.http_mcp_token = "rack-secret"
      rack_app = server.send(:build_rack_app, transport, "/mcp")
      env = Rack::MockRequest.env_for(
        "/mcp",
        method: "POST",
        "HTTP_AUTHORIZATION" => "Bearer rack-secret"
      )
      expect(transport).to receive(:handle_request).and_return([ 200, {}, [ "OK" ] ])
      status, = rack_app.call(env)
      expect(status).to eq(200)
    end
  end
end
