# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RailsAiBridge MCP production validation" do
  around do |example|
    saved_token = RailsAiBridge.configuration.http_mcp_token
    saved_req = RailsAiBridge.configuration.mcp.require_auth_in_production
    saved_resolver = RailsAiBridge.configuration.mcp.auth.token_resolver
    saved_jwt = RailsAiBridge.configuration.mcp.auth.jwt_decoder
    saved_strategy = RailsAiBridge.configuration.mcp.auth.strategy
    example.run
  ensure
    RailsAiBridge.configuration.http_mcp_token = saved_token
    RailsAiBridge.configuration.mcp.require_auth_in_production = saved_req
    RailsAiBridge.configuration.mcp.auth.token_resolver = saved_resolver
    RailsAiBridge.configuration.mcp.auth.jwt_decoder = saved_jwt
    RailsAiBridge.configuration.mcp.auth.strategy = saved_strategy
  end

  describe ".validate_mcp_require_auth_in_production!" do
    it "does nothing in non-production" do
      allow(Rails.env).to receive(:production?).and_return(false)
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      RailsAiBridge.configuration.http_mcp_token = nil
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.not_to raise_error
    end

    it "does nothing when require_auth_in_production is false" do
      allow(Rails.env).to receive(:production?).and_return(true)
      RailsAiBridge.configuration.mcp.require_auth_in_production = false
      RailsAiBridge.configuration.http_mcp_token = nil
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.not_to raise_error
    end

    it "raises when production, flag true, and no auth mechanism" do
      allow(Rails.env).to receive(:production?).and_return(true)
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.token_resolver = nil
      RailsAiBridge.configuration.mcp.auth.jwt_decoder = nil
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.to raise_error(
        RailsAiBridge::ConfigurationError,
        /require_auth_in_production/
      )
    end

    it "passes with static http_mcp_token" do
      allow(Rails.env).to receive(:production?).and_return(true)
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      RailsAiBridge.configuration.http_mcp_token = "secret"
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.not_to raise_error
    end

    it "passes with token_resolver only" do
      allow(Rails.env).to receive(:production?).and_return(true)
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.token_resolver = ->(_t) { nil }
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.not_to raise_error
    end

    it "passes with jwt_decoder only" do
      allow(Rails.env).to receive(:production?).and_return(true)
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.token_resolver = nil
      RailsAiBridge.configuration.mcp.auth.jwt_decoder = ->(_t) { nil }
      expect { RailsAiBridge.validate_mcp_require_auth_in_production! }.not_to raise_error
    end
  end

  describe ".validate_mcp_strategy_configuration!" do
    it "raises when strategy is :bearer_token without resolver or static token" do
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.strategy = :bearer_token
      RailsAiBridge.configuration.mcp.auth.token_resolver = nil
      expect { RailsAiBridge.validate_mcp_strategy_configuration! }.to raise_error(
        RailsAiBridge::ConfigurationError,
        /:bearer_token requires/
      )
    end

    it "passes when :bearer_token with token_resolver" do
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.strategy = :bearer_token
      RailsAiBridge.configuration.mcp.auth.token_resolver = ->(_t) { nil }
      expect { RailsAiBridge.validate_mcp_strategy_configuration! }.not_to raise_error
    end

    it "passes when :bearer_token with static token only" do
      RailsAiBridge.configuration.http_mcp_token = "secret"
      RailsAiBridge.configuration.mcp.auth.strategy = :bearer_token
      RailsAiBridge.configuration.mcp.auth.token_resolver = nil
      expect { RailsAiBridge.validate_mcp_strategy_configuration! }.not_to raise_error
    end

    it "does nothing when strategy is not :bearer_token" do
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.auth.strategy = :jwt
      RailsAiBridge.configuration.mcp.auth.jwt_decoder = nil
      expect { RailsAiBridge.validate_mcp_strategy_configuration! }.not_to raise_error
    end
  end
end
