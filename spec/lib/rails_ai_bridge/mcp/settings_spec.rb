# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::Settings do
  describe "defaults" do
    subject(:settings) { described_class.new }

    it "uses hybrid mode and balanced profile" do
      expect(settings.mode).to eq(:hybrid)
      expect(settings.security_profile).to eq(:balanced)
    end

    it "does not require auth in production by default" do
      expect(settings.require_auth_in_production).to eq(false)
    end

    it "disables MCP HTTP rate limiting by default" do
      expect(settings.rate_limit_max_requests).to be_nil
      expect(settings.rate_limit_window_seconds).to eq(60)
    end

    it "exposes nested auth config" do
      expect(settings.auth).to be_a(RailsAiBridge::Mcp::AuthConfig)
      expect(settings.auth.strategy).to be_nil
      expect(settings.auth.token_resolver).to be_nil
    end
  end

  describe "#auth_configure" do
    it "yields auth for DSL-style setup" do
      settings = described_class.new
      settings.auth_configure do |a|
        a.strategy = :bearer_token
        a.token_resolver = ->(t) { t == "x" ? :user : nil }
      end
      expect(settings.auth.strategy).to eq(:bearer_token)
      expect(settings.auth.token_resolver.call("x")).to eq(:user)
    end
  end
end
