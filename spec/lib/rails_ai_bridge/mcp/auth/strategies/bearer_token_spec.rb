# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::Auth::Strategies::BearerToken do
  # :reek:UtilityFunction
  def build_request(token: nil)
    headers = token ? { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } : {}
    Rack::Request.new(Rack::MockRequest.env_for('/mcp', headers))
  end

  describe 'static secret mode' do
    let(:strategy) do
      described_class.new(static_token_provider: -> { 'correct-secret' })
    end

    it 'returns ok for the correct token' do
      result = strategy.authenticate(build_request(token: 'correct-secret'))
      expect(result.success?).to be true
      expect(result.context).to eq(:static_bearer)
    end

    it 'returns fail(:wrong_token) for an incorrect token' do
      result = strategy.authenticate(build_request(token: 'wrong'))
      expect(result.failure?).to be true
      expect(result.error).to eq(:wrong_token)
    end

    it 'returns fail(:missing_token) when Authorization header is absent' do
      result = strategy.authenticate(build_request)
      expect(result.failure?).to be true
      expect(result.error).to eq(:missing_token)
    end

    it 'allows all requests when static_token_provider returns blank' do
      strategy = described_class.new(static_token_provider: -> {})
      result = strategy.authenticate(build_request)
      expect(result.success?).to be true
    end

    it 'returns fail(:missing_token) for a whitespace-only Bearer value' do
      result = strategy.authenticate(build_request(token: '   '))
      expect(result.failure?).to be true
      expect(result.error).to eq(:missing_token)
    end
  end

  describe 'token_resolver mode' do
    let(:user_context) { { id: 7, role: 'admin' } }
    let(:strategy) do
      described_class.new(
        static_token_provider: -> {},
        token_resolver: ->(token) { token == 'valid' ? user_context : nil }
      )
    end

    it 'returns ok with resolver context for a valid token' do
      result = strategy.authenticate(build_request(token: 'valid'))
      expect(result.success?).to be true
      expect(result.context).to eq(user_context)
    end

    it 'returns fail(:unauthorized) when resolver returns nil' do
      result = strategy.authenticate(build_request(token: 'bad'))
      expect(result.failure?).to be true
      expect(result.error).to eq(:unauthorized)
    end

    it 'returns fail(:unauthorized) when resolver returns false' do
      strategy = described_class.new(
        static_token_provider: -> {},
        token_resolver: ->(_token) { false }
      )
      result = strategy.authenticate(build_request(token: 'any'))
      expect(result.error).to eq(:unauthorized)
    end

    it 'returns fail(:missing_token) when Authorization header is absent' do
      result = strategy.authenticate(build_request)
      expect(result.error).to eq(:missing_token)
    end

    it 'returns fail(:resolver_error) when resolver raises' do
      bad_strategy = described_class.new(
        static_token_provider: -> {},
        token_resolver: ->(_t) { raise 'boom' }
      )
      result = bad_strategy.authenticate(build_request(token: 'any'))
      expect(result.error).to eq(:resolver_error)
    end
  end
end
