# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Service object that authenticates HTTP MCP requests.
    #
    # Consolidates strategy resolution, static-token lookup, and configuration
    # predicates into a single entry point — previously split across
    # +McpHttpAuth+ (utility helpers) and +Mcp::HttpAuth+ (strategy orchestrator),
    # both removed in v2.0.0.
    #
    # == Strategy priority (highest → lowest)
    #
    # 1. {Configuration#mcp_jwt_decoder} → {Auth::Strategies::Jwt}
    # 2. {Configuration#mcp_token_resolver} → {Auth::Strategies::BearerToken} (resolver mode)
    # 3. +config.http_mcp_token+ / +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ → {Auth::Strategies::BearerToken} (static mode)
    # 4. None configured → open access ({AuthResult.ok})
    #
    # == Security design notes
    #
    # * Static-token comparison uses +Digest::SHA256+ pre-hashing +
    #   +ActiveSupport::SecurityUtils.secure_compare+ (constant-time over
    #   fixed-length digests). This prevents token-length leakage but does NOT
    #   protect against brute-force guessing. Use +config.mcp.rate_limit_max_requests+
    #   for built-in per-IP rate limiting, or +rack-attack+ for distributed/stricter quotas.
    #
    # * The JWT strategy is decoder-only — this gem carries no JWT dependency.
    #   The host supplies a lambda; any +StandardError+ it raises is caught and
    #   surfaced as +:decode_error+, never propagated.
    #
    # @example Authenticating a Rack request
    #   result = Mcp::Authenticator.call(request)
    #   if result.success?
    #     # proceed — result.context may contain user/JWT payload
    #   else
    #     Mcp::Authenticator.unauthorized_rack_response
    #   end
    #
    # @see Auth::Strategies::BearerToken
    # @see Auth::Strategies::Jwt
    # @see AuthResult
    class Authenticator
      TOKEN_ENV_KEY = "RAILS_AI_BRIDGE_MCP_TOKEN"

      class << self
        # Authenticate an incoming Rack request against the configured strategy.
        #
        # @param request [Rack::Request]
        # @return [AuthResult] +.success?+ when authorized, +.failure?+ otherwise
        def call(request)
          strategy = resolve_strategy
          return AuthResult.ok(nil) if strategy.nil?

          strategy.authenticate(request)
        end

        # Returns +true+ when any auth mechanism is configured — static token,
        # resolver, or JWT decoder. Used by production-safety validators to confirm
        # the MCP endpoint is protected.
        #
        # Checks configuration *presence*, not runtime correctness. A resolver that
        # always returns +nil+ still counts as "configured."
        #
        # @return [Boolean]
        def any_configured?
          resolve_strategy.present?
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

        private

        # Selects the appropriate auth strategy from the current configuration.
        #
        # @return [Auth::BaseStrategy, nil] +nil+ means no auth is required (open access)
        def resolve_strategy(auth_cfg = RailsAiBridge.configuration.auth)
          if auth_cfg.mcp_jwt_decoder.present?
            return Auth::Strategies::Jwt.new(decoder: auth_cfg.mcp_jwt_decoder)
          end

          if auth_cfg.mcp_token_resolver.present?
            return Auth::Strategies::BearerToken.new(
              static_token_provider: -> { nil },
              token_resolver: auth_cfg.mcp_token_resolver
            )
          end

          token = effective_static_token(auth_cfg)
          return nil if token.blank?

          Auth::Strategies::BearerToken.new(
            static_token_provider: -> { token }
          )
        end

        # Returns the effective static Bearer token from ENV or configuration.
        # Environment variable takes precedence when present.
        #
        # @param auth_cfg [Config::Auth]
        # @return [String, nil] normalized token, or +nil+ when not configured
        def effective_static_token(auth_cfg = RailsAiBridge.configuration.auth)
          env_t = ENV.fetch(TOKEN_ENV_KEY, "").to_s.strip
          return env_t if env_t.present?

          auth_cfg.http_mcp_token.to_s.strip.presence
        end
      end
    end
  end
end
