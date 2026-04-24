# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds authentication and authorization settings for the MCP HTTP endpoint.
    #
    # Strategy priority (highest → lowest):
    # 1. {#mcp_jwt_decoder} — caller-supplied JWT decoding lambda
    # 2. {#mcp_token_resolver} — caller-supplied token resolution lambda
    # 3. {#http_mcp_token} / +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ — static bearer token
    # 4. None configured — open access
    #
    # @see Mcp::Authenticator
    class Auth
      # @return [String, nil] static bearer token for HTTP MCP auth
      attr_accessor :http_mcp_token

      # @return [Boolean] allow auto-mounting the MCP endpoint in production
      attr_accessor :allow_auto_mount_in_production

      # @return [Proc, nil] lambda resolving a raw bearer token to an auth context
      attr_accessor :mcp_token_resolver

      # @return [Proc, nil] lambda decoding a raw JWT to a payload hash
      attr_accessor :mcp_jwt_decoder

      def initialize
        @http_mcp_token = nil
        @allow_auto_mount_in_production = false
        @mcp_token_resolver           = nil
        @mcp_jwt_decoder              = nil
      end
    end
  end
end
