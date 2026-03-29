# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Orchestrates HTTP MCP authentication by resolving the active strategy
    # from the current {RailsAiBridge::Configuration} and delegating to it.
    #
    # Strategy priority (highest to lowest):
    # 1. {RailsAiBridge::Configuration#mcp_jwt_decoder} → {Auth::Strategies::Jwt}
    # 2. {RailsAiBridge::Configuration#mcp_token_resolver} → {Auth::Strategies::BearerToken} (resolver mode)
    # 3. +config.http_mcp_token+ / +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ → {Auth::Strategies::BearerToken} (static mode)
    # 4. No auth configured → open access ({AuthResult.ok})
    #
    # @see McpHttpAuth
    module HttpAuth
      module_function

      # Authenticates a Rack request using the configured strategy.
      #
      # @param request [Rack::Request]
      # @return [AuthResult]
      def authenticate(request)
        strategy = resolve_strategy
        return AuthResult.ok(nil) if strategy.nil?

        strategy.authenticate(request)
      end

      # Selects the appropriate strategy from the current configuration.
      #
      # @return [Auth::BaseStrategy, nil] +nil+ means no auth is required
      def resolve_strategy
        cfg = RailsAiBridge.configuration

        if cfg.mcp_jwt_decoder.present?
          return Auth::Strategies::Jwt.new(decoder: cfg.mcp_jwt_decoder)
        end

        if cfg.mcp_token_resolver.present?
          return Auth::Strategies::BearerToken.new(
            static_token_provider: -> { nil },
            token_resolver: cfg.mcp_token_resolver
          )
        end

        return nil unless McpHttpAuth.http_mcp_auth_configured?

        Auth::Strategies::BearerToken.new(
          static_token_provider: -> { McpHttpAuth.effective_http_mcp_token }
        )
      end
      private_class_method :resolve_strategy
    end
  end
end
