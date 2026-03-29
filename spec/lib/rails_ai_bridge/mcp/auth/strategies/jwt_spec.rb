# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::Auth::Strategies::Jwt do
  def build_request(token: nil)
    headers = token ? { "HTTP_AUTHORIZATION" => "Bearer #{token}" } : {}
    Rack::Request.new(Rack::MockRequest.env_for("/mcp", headers))
  end

  let(:payload) { { "sub" => "user_42" } }
  let(:decoder) { ->(token) { token == "valid.jwt.token" ? payload : nil } }
  let(:strategy) { described_class.new(decoder: decoder) }

  it "returns ok with decoded payload for a valid token" do
    result = strategy.authenticate(build_request(token: "valid.jwt.token"))
    expect(result.success?).to be true
    expect(result.context).to eq(payload)
  end

  it "returns fail(:unauthorized) when decoder returns nil" do
    result = strategy.authenticate(build_request(token: "bad.token"))
    expect(result.failure?).to be true
    expect(result.error).to eq(:unauthorized)
  end

  it "returns fail(:unauthorized) when decoder returns false" do
    strategy = described_class.new(decoder: ->(_t) { false })
    result = strategy.authenticate(build_request(token: "any"))
    expect(result.error).to eq(:unauthorized)
  end

  it "returns fail(:missing_token) when Authorization header is absent" do
    result = strategy.authenticate(build_request)
    expect(result.error).to eq(:missing_token)
  end

  it "returns fail(:misconfigured) when decoder is nil" do
    strategy = described_class.new(decoder: nil)
    result = strategy.authenticate(build_request(token: "any"))
    expect(result.error).to eq(:misconfigured)
  end

  it "returns fail(:decode_error) when decoder raises" do
    bad_strategy = described_class.new(decoder: ->(_t) { raise "invalid signature" })
    result = bad_strategy.authenticate(build_request(token: "any"))
    expect(result.error).to eq(:decode_error)
  end
end
