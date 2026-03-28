# frozen_string_literal: true

require "digest"

module RailsAiBridge
  module Mcp
    module Auth
      module Strategies
        # Compares +Authorization: Bearer+ to a shared secret and/or resolves a token via +token_resolver+.
        class BearerToken < BaseStrategy
          # Builds a strategy from a static secret provider and/or a host token resolver.
          # @param static_token_provider [Proc] callable returning +String+ secret or +nil+ (optional if +token_resolver+ is set)
          # @param token_resolver [Proc, nil] +->(token) { context_or_nil }+; return +nil+ or +false+ to deny
          # @return [void]
          def initialize(static_token_provider:, token_resolver: nil)
            @static_token_provider = static_token_provider
            @token_resolver = token_resolver
          end

          # Authenticates using +token_resolver+ when configured; otherwise compares Bearer to the static secret.
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

            ctx, resolve_error = resolve_token_context(token)
            return AuthResult.fail(resolve_error) if resolve_error
            return AuthResult.fail(:unauthorized) if ctx.nil? || ctx == false

            AuthResult.ok(ctx)
          end

          # Invokes +token_resolver+ and maps failures to a tuple (no uncaught exceptions).
          # @param token [String] raw Bearer credential (no +Bearer + prefix)
          # @return [Array] +[context, nil]+ on success; +[nil, :resolver_error]+ if the resolver raised
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

            return AuthResult.fail(:wrong_token) unless secure_compare_tokens(token, expected)

            AuthResult.ok(:static_bearer)
          end

          # Timing-safe equality on SHA256 digests so comparison does not leak raw token length.
          # @param received [String]
          # @param expected [String]
          # @return [Boolean]
          def secure_compare_tokens(received, expected)
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
