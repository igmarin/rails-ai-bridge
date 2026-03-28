# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::Auth::Strategies::Jwt do
  describe "#authenticate" do
    let(:decoder) { ->(token) { token == "good.jwt" ? { "sub" => "1" } : nil } }

    it "returns failure when Authorization is missing" do
      env = Rack::MockRequest.env_for("/mcp")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: decoder).authenticate(request)
      expect(result).to be_failure
      expect(result.error).to eq(:missing_token)
    end

    it "returns failure when decoder is nil" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer x")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: nil).authenticate(request)
      expect(result).to be_failure
      expect(result.error).to eq(:misconfigured)
    end

    it "returns success with payload as context when decoder returns a value" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer good.jwt")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: decoder).authenticate(request)
      expect(result).to be_success
      expect(result.context).to eq({ "sub" => "1" })
    end

    it "returns failure when decoder returns nil" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer bad.jwt")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: decoder).authenticate(request)
      expect(result).to be_failure
      expect(result.error).to eq(:unauthorized)
    end

    it "returns failure when decoder returns false" do
      false_decoder = ->(_t) { false }
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer x")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: false_decoder).authenticate(request)
      expect(result).to be_failure
      expect(result.error).to eq(:unauthorized)
    end

    it "returns decode_error when decoder raises StandardError" do
      bad_decoder = ->(_t) { raise StandardError, "bad sig" }
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer x")
      request = Rack::Request.new(env)
      result = described_class.new(decoder: bad_decoder).authenticate(request)
      expect(result).to be_failure
      expect(result.error).to eq(:decode_error)
    end
  end
end
