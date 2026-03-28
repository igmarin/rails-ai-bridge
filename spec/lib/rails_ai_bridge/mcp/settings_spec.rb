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
      expect(settings.effective_http_rate_limit_max_requests).to eq(0)
    end

    it "defaults http_log_json to false" do
      expect(settings.http_log_json).to eq(false)
    end

    it "exposes nested auth config" do
      expect(settings.auth).to be_a(RailsAiBridge::Mcp::AuthConfig)
      expect(settings.auth.strategy).to be_nil
      expect(settings.auth.token_resolver).to be_nil
    end
  end

  describe "effective HTTP rate limits" do
    it "returns 0 for nil max in hybrid mode when not in production" do
      allow(Rails.env).to receive(:production?).and_return(false)
      m = described_class.new
      m.mode = :hybrid
      m.security_profile = :balanced
      m.rate_limit_max_requests = nil

      expect(m.effective_http_rate_limit_max_requests).to eq(0)
    end

    it "returns profile default for nil max in hybrid mode in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      m = described_class.new
      m.mode = :hybrid
      m.security_profile = :strict
      m.rate_limit_max_requests = nil

      expect(m.effective_http_rate_limit_max_requests).to eq(60)
    end

    it "returns profile default for nil max in production mode regardless of Rails.env" do
      allow(Rails.env).to receive(:production?).and_return(false)
      m = described_class.new
      m.mode = :production
      m.security_profile = :relaxed
      m.rate_limit_max_requests = nil

      expect(m.effective_http_rate_limit_max_requests).to eq(1_200)
    end

    it "returns 0 for nil max in dev mode" do
      m = described_class.new
      m.mode = :dev
      m.security_profile = :strict
      m.rate_limit_max_requests = nil

      expect(m.effective_http_rate_limit_max_requests).to eq(0)
    end

    it "honors explicit positive integer over profile" do
      m = described_class.new
      m.mode = :production
      m.security_profile = :strict
      m.rate_limit_max_requests = 500

      expect(m.effective_http_rate_limit_max_requests).to eq(500)
    end

    it "disables when explicit zero" do
      allow(Rails.env).to receive(:production?).and_return(true)
      m = described_class.new
      m.mode = :hybrid
      m.security_profile = :strict
      m.rate_limit_max_requests = 0

      expect(m.effective_http_rate_limit_max_requests).to eq(0)
    end

    it "normalizes non-positive rate_limit_window_seconds to 60" do
      m = described_class.new
      m.rate_limit_window_seconds = 0

      expect(m.effective_http_rate_limit_window_seconds).to eq(60)
    end

    it "treats nil mode like hybrid for implicit suppression" do
      allow(Rails.env).to receive(:production?).and_return(false)
      m = described_class.new
      m.mode = nil
      m.rate_limit_max_requests = nil

      expect(m.http_rate_limit_implicitly_suppressed?).to be true
      expect(m.effective_http_rate_limit_max_requests).to eq(0)
    end

    it "treats nil security_profile like balanced for profile defaults" do
      allow(Rails.env).to receive(:production?).and_return(true)
      m = described_class.new
      m.mode = :hybrid
      m.security_profile = nil
      m.rate_limit_max_requests = nil

      expect(m.effective_http_rate_limit_max_requests).to eq(300)
    end

    it "accepts a numeric string for rate_limit_max_requests" do
      m = described_class.new
      m.mode = :production
      m.rate_limit_max_requests = "150"

      expect(m.effective_http_rate_limit_max_requests).to eq(150)
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
