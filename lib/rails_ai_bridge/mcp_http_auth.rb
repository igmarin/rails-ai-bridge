# frozen_string_literal: true

module RailsAiBridge
  # Shared HTTP MCP authentication for {Middleware} and {Server} Rack apps.
  # Authentication is delegated to {Mcp::HttpAuth}, which selects the active
  # strategy based on the current {Configuration}:
  #
  # 1. {Configuration#mcp_jwt_decoder} → JWT strategy
  # 2. {Configuration#mcp_token_resolver} → Bearer + resolver
  # 3. +http_mcp_token+ / +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ → static Bearer
  # 4. None configured → open access (local dev compatibility)
  module McpHttpAuth
    TOKEN_ENV_KEY = "RAILS_AI_BRIDGE_MCP_TOKEN"

    module_function

    # Returns the effective static Bearer token from ENV or configuration.
    # Environment variable takes precedence when present.
    #
    # @return [String, nil] normalized token, or +nil+ when not configured
    def effective_http_mcp_token
      env_t = ENV.fetch(TOKEN_ENV_KEY, "").to_s.strip
      return env_t if env_t.present?

      RailsAiBridge.configuration.http_mcp_token.to_s.strip.presence
    end

    # Returns +true+ when a static Bearer token is configured via ENV or config.
    #
    # @return [Boolean]
    def http_mcp_auth_configured?
      effective_http_mcp_token.present?
    end

    # Returns +true+ when ANY auth mechanism is configured — static token, resolver, or JWT decoder.
    # Used by production-safety validators to confirm the MCP endpoint is protected.
    #
    # This checks configuration *presence*, not runtime correctness. A resolver that always
    # returns +nil+ still counts as configured; actual auth enforcement happens per-request
    # via {Mcp::HttpAuth}.
    #
    # @return [Boolean]
    def any_auth_configured?
      cfg = RailsAiBridge.configuration
      http_mcp_auth_configured? ||
        cfg.mcp_token_resolver.present? ||
        cfg.mcp_jwt_decoder.present?
    end

    # Verifies whether an incoming Rack request is authorized for HTTP MCP access.
    # Delegates to {Mcp::HttpAuth} which selects the active auth strategy in priority order:
    # +mcp_jwt_decoder+ > +mcp_token_resolver+ > +http_mcp_token+/ENV > open access.
    #
    # @param request [Rack::Request]
    # @return [Boolean] +true+ when auth is not configured or the credential is accepted
    def authorized_request?(request)
      Mcp::HttpAuth.authenticate(request).success?
    end

    # Builds a Rack 401 response for unauthenticated HTTP MCP requests.
    #
    # @return [Array<(Integer, Hash{String => String}, Array<String>)>] Rack response tuple
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
