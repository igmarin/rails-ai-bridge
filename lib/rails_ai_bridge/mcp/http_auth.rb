# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Orchestrates HTTP MCP authentication using a resolved strategy (JWT, Bearer resolver, or static secret).
    module HttpAuth
      ENV_CONTEXT_KEY = "rails_ai_bridge.mcp.context"

      module_function

      # @param request [Rack::Request]
      # @return [AuthResult]
      def authenticate(request)
        env = request.env
        env.delete(ENV_CONTEXT_KEY)

        strategy = resolve_strategy
        if strategy.nil?
          return AuthResult.ok(nil)
        end

        result = strategy.authenticate(request)
        env[ENV_CONTEXT_KEY] = result.context if result.success?
        result
      end

      # @return [RailsAiBridge::Mcp::Auth::Strategies::BearerToken, RailsAiBridge::Mcp::Auth::Strategies::Jwt, nil]
      def resolve_strategy
        a = RailsAiBridge.configuration.mcp.auth

        if a.strategy != :static_bearer
          if a.strategy == :jwt || (a.strategy.nil? && a.jwt_decoder.present?)
            return Auth::Strategies::Jwt.new(decoder: a.jwt_decoder)
          end

          if a.token_resolver.present? && [ :bearer_token, nil ].include?(a.strategy)
            return Auth::Strategies::BearerToken.new(
              static_token_provider: -> { nil },
              token_resolver: a.token_resolver
            )
          end
        end

        return nil unless McpHttpAuth.http_mcp_auth_configured?

        Auth::Strategies::BearerToken.new(
          static_token_provider: -> { McpHttpAuth.effective_http_mcp_token },
          token_resolver: nil
        )
      end
      private_class_method :resolve_strategy
    end
  end
end
