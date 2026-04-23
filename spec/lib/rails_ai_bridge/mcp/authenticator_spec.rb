# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::Authenticator do
  def build_request(token: nil)
    headers = token ? { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } : {}
    Rack::Request.new(Rack::MockRequest.env_for('/mcp', headers))
  end

  around do |example|
    saved_token    = RailsAiBridge.configuration.http_mcp_token
    saved_resolver = RailsAiBridge.configuration.mcp_token_resolver
    saved_decoder  = RailsAiBridge.configuration.mcp_jwt_decoder
    saved_env      = ENV.fetch('RAILS_AI_BRIDGE_MCP_TOKEN', nil)
    ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
    example.run
  ensure
    saved_env ? (ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = saved_env) : ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
    RailsAiBridge.configuration.http_mcp_token     = saved_token
    RailsAiBridge.configuration.mcp_token_resolver = saved_resolver
    RailsAiBridge.configuration.mcp_jwt_decoder    = saved_decoder
  end

  describe '.call' do
    context 'when no auth is configured' do
      before do
        RailsAiBridge.configuration.http_mcp_token     = nil
        RailsAiBridge.configuration.mcp_token_resolver = nil
        RailsAiBridge.configuration.mcp_jwt_decoder    = nil
      end

      it 'returns a successful result (open access)' do
        expect(described_class.call(build_request)).to be_success
      end
    end

    context 'when http_mcp_token (static) is configured' do
      before { RailsAiBridge.configuration.http_mcp_token = 's3cr3t' }

      it 'accepts matching Bearer token' do
        expect(described_class.call(build_request(token: 's3cr3t'))).to be_success
      end

      it 'rejects wrong token' do
        expect(described_class.call(build_request(token: 'wrong'))).to be_failure
      end

      it 'rejects missing Authorization' do
        expect(described_class.call(build_request)).to be_failure
      end
    end

    context 'when mcp_token_resolver is configured' do
      let(:user_ctx) { { id: 1 } }

      before do
        RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t == 'valid' ? user_ctx : nil }
      end

      it 'returns success with resolver context for valid token' do
        result = described_class.call(build_request(token: 'valid'))
        expect(result).to be_success
        expect(result.context).to eq(user_ctx)
      end

      it 'returns failure for unknown token' do
        expect(described_class.call(build_request(token: 'bad'))).to be_failure
      end
    end

    context 'when mcp_jwt_decoder is configured' do
      let(:payload) { { 'sub' => 'u1' } }

      before do
        RailsAiBridge.configuration.mcp_jwt_decoder = ->(t) { t == 'good.jwt' ? payload : nil }
      end

      it 'returns success with decoded payload' do
        result = described_class.call(build_request(token: 'good.jwt'))
        expect(result).to be_success
        expect(result.context).to eq(payload)
      end

      it 'returns failure for invalid JWT' do
        expect(described_class.call(build_request(token: 'bad'))).to be_failure
      end
    end
  end

  describe 'strategy priority' do
    it 'uses JWT over token_resolver' do
      RailsAiBridge.configuration.mcp_jwt_decoder = ->(t) { t == 'jwt' ? { jwt: true } : nil }
      RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t == 'jwt' ? { resolver: true } : nil }

      result = described_class.call(build_request(token: 'jwt'))
      expect(result.context).to eq({ jwt: true })
    end

    it 'uses token_resolver over static secret' do
      RailsAiBridge.configuration.http_mcp_token     = 'static'
      RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t == 'resolver' ? { via: :resolver } : nil }

      result = described_class.call(build_request(token: 'resolver'))
      expect(result.context).to eq({ via: :resolver })
    end

    it 'ENV token takes precedence over config.http_mcp_token' do
      ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = 'env-token'
      RailsAiBridge.configuration.http_mcp_token = 'config-token'

      expect(described_class.call(build_request(token: 'env-token'))).to be_success
      expect(described_class.call(build_request(token: 'config-token'))).to be_failure
    end
  end

  describe '.any_configured?' do
    before do
      RailsAiBridge.configuration.http_mcp_token     = nil
      RailsAiBridge.configuration.mcp_token_resolver = nil
      RailsAiBridge.configuration.mcp_jwt_decoder    = nil
    end

    it 'returns false when no auth mechanism is configured' do
      expect(described_class.any_configured?).to be false
    end

    it 'returns true when http_mcp_token is set' do
      RailsAiBridge.configuration.http_mcp_token = 'tok'
      expect(described_class.any_configured?).to be true
    end

    it 'returns true when mcp_token_resolver is set' do
      RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t }
      expect(described_class.any_configured?).to be true
    end

    it 'returns true when mcp_jwt_decoder is set' do
      RailsAiBridge.configuration.mcp_jwt_decoder = ->(t) { t }
      expect(described_class.any_configured?).to be true
    end

    it 'returns true when ENV token is set' do
      ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = 'env-only'
      expect(described_class.any_configured?).to be true
    end
  end

  describe '.unauthorized_rack_response' do
    it 'returns a 401 JSON response with WWW-Authenticate header' do
      status, headers, body = described_class.unauthorized_rack_response

      expect(status).to eq(401)
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['WWW-Authenticate']).to include('Bearer')
      expect(body.first).to include('Unauthorized')
    end
  end

  describe 'resolve_strategy visibility' do
    it 'is private and not callable from outside' do
      expect(described_class.private_methods).to include(:resolve_strategy)
    end
  end
end
