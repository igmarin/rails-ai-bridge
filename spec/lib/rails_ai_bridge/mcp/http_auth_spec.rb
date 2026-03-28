# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::HttpAuth do
  around do |example|
    saved_env = ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]
    saved_cfg_token = RailsAiBridge.configuration.http_mcp_token
    saved_resolver = RailsAiBridge.configuration.mcp.auth.token_resolver
    saved_strategy = RailsAiBridge.configuration.mcp.auth.strategy
    saved_jwt = RailsAiBridge.configuration.mcp.auth.jwt_decoder
    ENV.delete("RAILS_AI_BRIDGE_MCP_TOKEN")
    example.run
  ensure
    if saved_env
      ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] = saved_env
    else
      ENV.delete("RAILS_AI_BRIDGE_MCP_TOKEN")
    end
    RailsAiBridge.configuration.http_mcp_token = saved_cfg_token
    RailsAiBridge.configuration.mcp.auth.token_resolver = saved_resolver
    RailsAiBridge.configuration.mcp.auth.strategy = saved_strategy
    RailsAiBridge.configuration.mcp.auth.jwt_decoder = saved_jwt
  end

  describe ".authenticate" do
    let(:key) { described_class::ENV_CONTEXT_KEY }

    context "when no HTTP MCP token is configured" do
      before { RailsAiBridge.configuration.http_mcp_token = nil }

      it "returns success without requiring Authorization" do
        env = Rack::MockRequest.env_for("/mcp")
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_success
        expect(result.context).to be_nil
        expect(env[key]).to be_nil
      end
    end

    context "when token is configured" do
      before { RailsAiBridge.configuration.http_mcp_token = "correct-token" }

      it "returns failure when Authorization is missing" do
        env = Rack::MockRequest.env_for("/mcp")
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(env[key]).to be_nil
      end

      it "returns failure for wrong Bearer token" do
        env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer wrong")
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(env[key]).to be_nil
      end

      it "returns success and sets rack env context when Bearer matches" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer correct-token"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_success
        expect(result.context).to eq(:static_bearer)
        expect(env[key]).to eq(:static_bearer)
      end
    end

    context "when token_resolver is configured without static token" do
      before do
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp.auth.strategy = :bearer_token
        RailsAiBridge.configuration.mcp.auth.token_resolver = lambda do |token|
          token == "api-ok" ? :resolved_user : nil
        end
      end

      it "returns success with resolver context when token maps" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer api-ok"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_success
        expect(result.context).to eq(:resolved_user)
        expect(env[key]).to eq(:resolved_user)
      end

      it "returns failure when resolver returns nil" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer unknown"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(env[key]).to be_nil
      end

      it "returns failure when resolver returns false" do
        RailsAiBridge.configuration.mcp.auth.token_resolver = ->(_t) { false }
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer any"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(result.error).to eq(:unauthorized)
        expect(env[key]).to be_nil
      end

      it "returns failure when resolver raises (no exception propagates)" do
        RailsAiBridge.configuration.mcp.auth.token_resolver = ->(_t) { raise StandardError, "simulated resolver failure" }
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer any-token"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(result.error).to eq(:resolver_error)
        expect(env[key]).to be_nil
      end
    end

    context "when jwt_decoder is configured (strategy :jwt)" do
      before do
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp.auth.token_resolver = nil
        RailsAiBridge.configuration.mcp.auth.strategy = :jwt
        RailsAiBridge.configuration.mcp.auth.jwt_decoder = lambda do |token|
          token == "valid" ? { "sub" => "user-1" } : nil
        end
      end

      it "returns success and sets context to decoded payload" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer valid"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_success
        expect(result.context).to eq({ "sub" => "user-1" })
        expect(env[key]).to eq({ "sub" => "user-1" })
      end

      it "returns failure when decode yields nil" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer other"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_failure
        expect(env[key]).to be_nil
      end
    end

    context "when jwt_decoder is set with strategy nil (auto)" do
      before do
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp.auth.strategy = nil
        RailsAiBridge.configuration.mcp.auth.token_resolver = nil
        RailsAiBridge.configuration.mcp.auth.jwt_decoder = ->(t) { t == "auto" ? { "ok" => true } : nil }
      end

      it "uses JWT strategy before static or resolver" do
        env = Rack::MockRequest.env_for(
          "/mcp",
          "HTTP_AUTHORIZATION" => "Bearer auto"
        )
        request = Rack::Request.new(env)
        result = described_class.authenticate(request)
        expect(result).to be_success
        expect(result.context).to eq({ "ok" => true })
      end
    end
  end
end
