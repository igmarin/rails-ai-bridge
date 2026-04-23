# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RailsAiBridge auto_mount production validation' do
  describe '.validate_auto_mount_configuration!' do
    around do |example|
      saved_env      = ENV.fetch('RAILS_AI_BRIDGE_MCP_TOKEN', nil)
      saved_auto     = RailsAiBridge.configuration.auto_mount
      saved_allow    = RailsAiBridge.configuration.allow_auto_mount_in_production
      saved_http     = RailsAiBridge.configuration.http_mcp_token
      saved_resolver = RailsAiBridge.configuration.mcp_token_resolver
      saved_decoder  = RailsAiBridge.configuration.mcp_jwt_decoder
      ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
      example.run
    ensure
      saved_env ? (ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = saved_env) : ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
      RailsAiBridge.configuration.auto_mount = saved_auto
      RailsAiBridge.configuration.allow_auto_mount_in_production = saved_allow
      RailsAiBridge.configuration.http_mcp_token              = saved_http
      RailsAiBridge.configuration.mcp_token_resolver          = saved_resolver
      RailsAiBridge.configuration.mcp_jwt_decoder             = saved_decoder
    end

    it 'does nothing when auto_mount is false' do
      RailsAiBridge.configuration.auto_mount = false
      expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
    end

    it 'does nothing in non-production when auto_mount is true without token' do
      RailsAiBridge.configuration.auto_mount = true
      RailsAiBridge.configuration.http_mcp_token = nil
      expect(Rails.env.production?).to be(false)
      expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
    end

    context 'when Rails.env is production' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'raises when auto_mount is true and allow_auto_mount_in_production is false' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = false
        RailsAiBridge.configuration.http_mcp_token = 'tok'

        expect { RailsAiBridge.validate_auto_mount_configuration! }
          .to raise_error(RailsAiBridge::ConfigurationError, /allow_auto_mount_in_production/)
      end

      it 'raises when auto_mount is true and token is blank' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = nil

        expect { RailsAiBridge.validate_auto_mount_configuration! }
          .to raise_error(RailsAiBridge::ConfigurationError, /http_mcp_token|RAILS_AI_BRIDGE_MCP_TOKEN/)
      end

      it 'passes when auto_mount, allow flag, and token are set' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = 'secure'

        expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
      end

      it 'passes when token comes only from ENV' do
        ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = 'env-only'
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = nil

        expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
      end

      it 'passes when mcp_token_resolver is configured (no static token needed)' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t }

        expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
      end

      it 'passes when mcp_jwt_decoder is configured (no static token needed)' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp_jwt_decoder = ->(t) { t }

        expect { RailsAiBridge.validate_auto_mount_configuration! }.not_to raise_error
      end

      it 'raises when auto_mount is true, allow flag set, but no auth at all' do
        RailsAiBridge.configuration.auto_mount = true
        RailsAiBridge.configuration.allow_auto_mount_in_production = true
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp_token_resolver = nil
        RailsAiBridge.configuration.mcp_jwt_decoder = nil

        expect { RailsAiBridge.validate_auto_mount_configuration! }
          .to raise_error(RailsAiBridge::ConfigurationError, /auth/)
      end
    end
  end

  describe '.validate_http_mcp_server_in_production!' do
    around do |example|
      saved_env      = ENV.fetch('RAILS_AI_BRIDGE_MCP_TOKEN', nil)
      saved_http     = RailsAiBridge.configuration.http_mcp_token
      saved_resolver = RailsAiBridge.configuration.mcp_token_resolver
      saved_decoder  = RailsAiBridge.configuration.mcp_jwt_decoder
      ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
      example.run
    ensure
      saved_env ? (ENV['RAILS_AI_BRIDGE_MCP_TOKEN'] = saved_env) : ENV.delete('RAILS_AI_BRIDGE_MCP_TOKEN')
      RailsAiBridge.configuration.http_mcp_token     = saved_http
      RailsAiBridge.configuration.mcp_token_resolver = saved_resolver
      RailsAiBridge.configuration.mcp_jwt_decoder    = saved_decoder
    end

    around do |example|
      saved_require = RailsAiBridge.configuration.mcp.require_auth_in_production
      example.run
    ensure
      RailsAiBridge.configuration.mcp.require_auth_in_production = saved_require
    end

    it 'does nothing outside production when require_auth_in_production is false' do
      expect(Rails.env.production?).to be(false)
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.require_auth_in_production = false
      expect { RailsAiBridge.validate_http_mcp_server_in_production! }.not_to raise_error
    end

    it 'raises outside production when require_auth_in_production is true and no auth is configured' do
      expect(Rails.env.production?).to be(false)
      RailsAiBridge.configuration.http_mcp_token = nil
      RailsAiBridge.configuration.mcp.require_auth_in_production = true

      expect { RailsAiBridge.validate_http_mcp_server_in_production! }
        .to raise_error(RailsAiBridge::ConfigurationError, /HTTP MCP in production/)
    end

    it 'passes outside production when require_auth_in_production is true and token is configured' do
      RailsAiBridge.configuration.http_mcp_token = 'dev-token'
      RailsAiBridge.configuration.mcp.require_auth_in_production = true
      expect { RailsAiBridge.validate_http_mcp_server_in_production! }.not_to raise_error
    end

    context 'when Rails.env is production' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'raises when no MCP token is configured' do
        RailsAiBridge.configuration.http_mcp_token = nil

        expect { RailsAiBridge.validate_http_mcp_server_in_production! }
          .to raise_error(RailsAiBridge::ConfigurationError, /HTTP MCP in production/)
      end

      it 'passes when http_mcp_token is set' do
        RailsAiBridge.configuration.http_mcp_token = 'ok'

        expect { RailsAiBridge.validate_http_mcp_server_in_production! }.not_to raise_error
      end

      it 'passes when mcp_token_resolver is configured' do
        RailsAiBridge.configuration.mcp_token_resolver = ->(t) { t }

        expect { RailsAiBridge.validate_http_mcp_server_in_production! }.not_to raise_error
      end

      it 'passes when mcp_jwt_decoder is configured' do
        RailsAiBridge.configuration.mcp_jwt_decoder = ->(t) { t }

        expect { RailsAiBridge.validate_http_mcp_server_in_production! }.not_to raise_error
      end

      it 'raises when no auth mechanism is configured at all' do
        RailsAiBridge.configuration.http_mcp_token = nil
        RailsAiBridge.configuration.mcp_token_resolver = nil
        RailsAiBridge.configuration.mcp_jwt_decoder = nil

        expect { RailsAiBridge.validate_http_mcp_server_in_production! }
          .to raise_error(RailsAiBridge::ConfigurationError, /HTTP MCP in production/)
      end
    end
  end
end
