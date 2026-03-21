# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::McpHttpAuth do
  around do |example|
    saved_env = ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]
    saved_cfg_token = RailsAiBridge.configuration.http_mcp_token
    ENV.delete("RAILS_AI_BRIDGE_MCP_TOKEN")
    example.run
  ensure
    if saved_env
      ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] = saved_env
    else
      ENV.delete("RAILS_AI_BRIDGE_MCP_TOKEN")
    end
    RailsAiBridge.configuration.http_mcp_token = saved_cfg_token
  end

  describe ".effective_http_mcp_token" do
    it "returns nil when neither ENV nor config is set" do
      RailsAiBridge.configuration.http_mcp_token = nil
      expect(described_class.effective_http_mcp_token).to be_nil
    end

    it "uses config.http_mcp_token when ENV is unset" do
      RailsAiBridge.configuration.http_mcp_token = "  secret  "
      expect(described_class.effective_http_mcp_token).to eq("secret")
    end

    it "prefers ENV over config when both are set" do
      ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] = "from-env"
      RailsAiBridge.configuration.http_mcp_token = "from-config"
      expect(described_class.effective_http_mcp_token).to eq("from-env")
    end
  end

  describe ".authorized_request?" do
    let(:request) { Rack::Request.new(Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => auth_header)) }
    let(:auth_header) { nil }

    before { RailsAiBridge.configuration.http_mcp_token = nil }

    context "when no token is configured" do
      it "allows the request" do
        expect(described_class.authorized_request?(request)).to eq(true)
      end
    end

    context "when token is configured" do
      before { RailsAiBridge.configuration.http_mcp_token = "correct-token" }

      it "rejects missing Authorization" do
        expect(described_class.authorized_request?(Rack::Request.new(Rack::MockRequest.env_for("/mcp")))).to eq(false)
      end

      it "rejects wrong Bearer token" do
        env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer wrong")
        expect(described_class.authorized_request?(Rack::Request.new(env))).to eq(false)
      end

      it "accepts matching Bearer token" do
        env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer correct-token")
        expect(described_class.authorized_request?(Rack::Request.new(env))).to eq(true)
      end
    end
  end
end
