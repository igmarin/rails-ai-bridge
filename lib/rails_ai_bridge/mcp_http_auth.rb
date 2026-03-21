# frozen_string_literal: true

require "digest"

module RailsAiBridge
  # Shared HTTP MCP authentication for {Middleware} and {Server} Rack apps.
  # When +http_mcp_token+ or +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ is set, requests must send
  # +Authorization: Bearer <token>+. When unset, requests are allowed (local dev compatibility).
  module McpHttpAuth
    TOKEN_ENV_KEY = "RAILS_AI_BRIDGE_MCP_TOKEN"

    module_function

    # Returns the effective HTTP MCP Bearer token.
    # Environment token takes precedence over configuration when present.
    #
    # @return [String, nil] normalized token, or +nil+ when auth is not configured
    def effective_http_mcp_token
      env_t = ENV.fetch(TOKEN_ENV_KEY, "").to_s.strip
      return env_t if env_t.present?

      RailsAiBridge.configuration.http_mcp_token.to_s.strip.presence
    end

    # Indicates whether HTTP MCP auth is currently configured.
    #
    # @return [Boolean] true when an effective token exists
    def http_mcp_auth_configured?
      effective_http_mcp_token.present?
    end

    # Verifies whether an incoming Rack request is authorized for HTTP MCP access.
    #
    # @param request [Rack::Request] request to validate
    # @return [Boolean] true when auth is not configured or the Bearer token matches
    def authorized_request?(request)
      return true unless http_mcp_auth_configured?

      auth = request.get_header("HTTP_AUTHORIZATION")
      return false if auth.blank?

      match = auth.match(/\ABearer\s+(.+)\z/i)
      return false unless match

      received = match[1].to_s.strip
      expected = effective_http_mcp_token.to_s
      return false if received.blank? || expected.blank?

      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(received),
        Digest::SHA256.hexdigest(expected)
      )
    end

    # Builds a Rack-compatible unauthorized response for HTTP MCP endpoints.
    #
    # @return [Array<(Integer, Hash{String => String}, Array<String>)>] rack response tuple
    def unauthorized_rack_response
      [
        401,
        {
          "Content-Type" => "application/json",
          "WWW-Authenticate" => 'Bearer realm="rails-ai-bridge-mcp"'
        },
        [ '{"error":"Unauthorized"}' ]
      ]
    end
  end
end
