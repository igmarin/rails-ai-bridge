# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    module Auth
      module Strategies
        # Decodes a Bearer token via a host-provided lambda (no JWT gem required).
        #
        # Example: +->(token) { JWT.decode(token, key, true, algorithm: "HS256").first rescue nil }+
        class Jwt < BaseStrategy
          # @param decoder [Proc, nil] +->(raw_bearer_string) { payload_or_nil }+
          def initialize(decoder:)
            @decoder = decoder
          end

          # @param request [Rack::Request]
          # @return [AuthResult]
          def authenticate(request)
            token = extract_bearer(request)
            return AuthResult.fail(:missing_token) if token.blank?
            return AuthResult.fail(:misconfigured) if @decoder.nil?

            payload, decode_error = decode_token(token)
            return AuthResult.fail(decode_error) if decode_error
            return AuthResult.fail(:unauthorized) if payload.nil? || payload == false

            AuthResult.ok(payload)
          end

          private

          # Runs the host decoder; never raises.
          #
          # @return [Array(Object, Symbol, nil)] +[payload, nil]+ on success path, or +[nil, :decode_error]+ if the decoder raised
          def decode_token(token)
            [ @decoder.call(token), nil ]
          rescue StandardError
            [ nil, :decode_error ]
          end
        end
      end
    end
  end
end
