# frozen_string_literal: true

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
      Mcp::HttpAuth.authenticate(request).success?
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

    # Rack 403 after authentication succeeded but {RailsAiBridge::Configuration#mcp} +authorize+ rejected.
    #
    # @return [Array<(Integer, Hash{String => String}, Array<String>)>]
    def forbidden_rack_response
      [
        403,
        { "Content-Type" => "application/json" },
        [ '{"error":"Forbidden"}' ]
      ]
    end

    # JSON 429 when the MCP HTTP rate limiter rejects a request.
    #
    # @param retry_after [Integer, nil] optional +Retry-After+ header value in seconds
    # @return [Array<(Integer, Hash{String => String}, Array<String>)>]
    def rate_limited_rack_response(retry_after: nil)
      headers = { "Content-Type" => "application/json" }
      headers["Retry-After"] = retry_after.to_s if retry_after&.positive?

      [
        429,
        headers,
        [ '{"error":"Too Many Requests"}' ]
      ]
    end
  end
end
