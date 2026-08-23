# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::Auth::BaseStrategy do
  # :reek:UtilityFunction
  def build_request(headers = {})
    Rack::Request.new(Rack::MockRequest.env_for('/mcp', headers))
  end

  let(:strategy) { described_class.new }

  describe '#extract_bearer' do
    it 'extracts the token from a valid Bearer header' do
      request = build_request('HTTP_AUTHORIZATION' => 'Bearer my-secret-token')

      expect(strategy.extract_bearer(request)).to eq('my-secret-token')
    end

    it 'returns nil when the Authorization header is absent' do
      expect(strategy.extract_bearer(build_request)).to be_nil
    end

    it 'returns nil when the Authorization header is blank' do
      expect(strategy.extract_bearer(build_request('HTTP_AUTHORIZATION' => ''))).to be_nil
    end

    it 'returns nil for a malformed (non-Bearer) Authorization header' do
      request = build_request('HTTP_AUTHORIZATION' => 'Basic dXNlcjpwYXNz')

      expect(strategy.extract_bearer(request)).to be_nil
    end

    it 'strips whitespace from the extracted token' do
      request = build_request('HTTP_AUTHORIZATION' => 'Bearer   padded-token   ')

      expect(strategy.extract_bearer(request)).to eq('padded-token')
    end

    it 'handles case-insensitive Bearer prefix' do
      request = build_request('HTTP_AUTHORIZATION' => 'bearer lowercase-token')

      expect(strategy.extract_bearer(request)).to eq('lowercase-token')
    end
  end
end
