# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/middleware"

RSpec.describe RailsAiBridge::Middleware do
  let(:inner_app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "OK" ] ] } }
  let(:middleware) { described_class.new(inner_app) }

  describe "#call" do
    it "passes non-MCP requests through to the app" do
      env = Rack::MockRequest.env_for("/users")
      status, _headers, body = middleware.call(env)
      expect(status).to eq(200)
      expect(body).to eq([ "OK" ])
    end

    it "intercepts requests at the configured MCP path" do
      env = Rack::MockRequest.env_for("/mcp", method: "POST", input: "{}")
      status, _headers, _body = middleware.call(env)
      # MCP transport will respond (possibly 400/405 for invalid request)
      # but it should NOT be 200 from the inner app
      expect(status).not_to eq(200)
    end
  end
end
