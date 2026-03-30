# frozen_string_literal: true

require "digest"

module RailsAiBridge
  module Mcp
    module Auth
      module Strategies
        # Authenticates HTTP MCP requests using a Bearer token.
        #
        # Supports two modes, selected at construction time:
        #
        # * **Resolver mode** — when +token_resolver+ is provided the raw Bearer
        #   string is passed to the lambda; a truthy return value becomes the
        #   {AuthResult#context}. Use this to look up a user from a database token
        #   or validate an opaque API key via a third-party service.
        #
        # * **Static secret mode** — when no resolver is given the token is
        #   compared timing-safely to the value returned by +static_token_provider+.
        #   Suitable for shared secrets in +config.http_mcp_token+ / ENV.
        #
        # @example Static secret
        #   BearerToken.new(static_token_provider: -> { Rails.application.credentials.mcp_token })
        #
        # @example Resolver (Devise)
        #   BearerToken.new(
        #     static_token_provider: -> { nil },
        #     token_resolver: ->(token) { User.find_by(api_token: token) }
        #   )
        class BearerToken < BaseStrategy
          # @param static_token_provider [Proc] callable returning +String+ or +nil+
          # @param token_resolver [Proc, nil] +->(raw_token) { context_or_nil_or_false }+
          def initialize(static_token_provider:, token_resolver: nil)
            @static_token_provider = static_token_provider
            @token_resolver = token_resolver
          end

          # Authenticates the incoming request.
          #
          # @param request [Rack::Request]
          # @return [AuthResult]
          def authenticate(request)
            return authenticate_via_resolver(request) if @token_resolver

            authenticate_via_static_secret(request)
          end

          private

          def authenticate_via_resolver(request)
            token = extract_bearer(request)
            return AuthResult.fail(:missing_token) if token.blank?

            ctx, err = resolve_token_context(token)
            return AuthResult.fail(err) if err
            return AuthResult.fail(:unauthorized) if ctx.nil? || ctx == false

            AuthResult.ok(ctx)
          end

          # Calls +token_resolver+ and wraps exceptions so callers always get an {AuthResult}.
          # Any +StandardError+ (including programmer errors) is caught and surfaced as
          # +:resolver_error+ rather than propagating to the caller.
          #
          # @param token [String] raw Bearer credential (no +"Bearer "+ prefix)
          # @return [Array(Object, nil)] +[context, nil]+ on success
          # @return [Array(nil, Symbol)] +[nil, :resolver_error]+ when the resolver raised
          def resolve_token_context(token)
            [ @token_resolver.call(token), nil ]
          rescue StandardError
            [ nil, :resolver_error ]
          end

          def authenticate_via_static_secret(request)
            expected = @static_token_provider.call.to_s
            return AuthResult.ok(nil) if expected.blank?

            token = extract_bearer(request)
            return AuthResult.fail(:missing_token) if token.blank?
            return AuthResult.fail(:wrong_token) unless secure_compare(token, expected)

            AuthResult.ok(:static_bearer)
          end

          # Timing-safe comparison over SHA-256 digests.
          #
          # Pre-hashing normalises both inputs to 64-hex-character strings so
          # +secure_compare+ never leaks the original token length via timing.
          # This is the same pattern used by Devise and Rails session tokens.
          #
          # **This does NOT protect against brute-force guessing.** Host
          # applications MUST add rate limiting (e.g. Rack::Attack) on the MCP
          # endpoint in production.
          def secure_compare(received, expected)
            ActiveSupport::SecurityUtils.secure_compare(
              Digest::SHA256.hexdigest(received),
              Digest::SHA256.hexdigest(expected)
            )
          end
        end
      end
    end
  end
end
