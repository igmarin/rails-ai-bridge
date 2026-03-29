# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    module Auth
      module Strategies
        # Authenticates HTTP MCP requests by decoding a Bearer JWT via a
        # host-provided lambda. No JWT gem is required by this gem — the host
        # application supplies its own decoding logic.
        #
        # @example Using the +jwt+ gem
        #   config.mcp_jwt_decoder = ->(token) do
        #     JWT.decode(token, Rails.application.credentials.jwt_secret, true, algorithm: "HS256").first
        #   rescue JWT::DecodeError
        #     nil
        #   end
        class Jwt < BaseStrategy
          # @param decoder [Proc, nil] +->(raw_bearer_string) { payload_or_nil_or_false }+
          def initialize(decoder:)
            @decoder = decoder
          end

          # Authenticates the incoming request.
          #
          # @param request [Rack::Request]
          # @return [AuthResult]
          def authenticate(request)
            token = extract_bearer(request)
            return AuthResult.fail(:missing_token) if token.blank?
            return AuthResult.fail(:misconfigured) if @decoder.nil?

            payload, err = decode_token(token)
            return AuthResult.fail(err) if err
            return AuthResult.fail(:unauthorized) if payload.nil? || payload == false

            AuthResult.ok(payload)
          end

          private

          # Calls +@decoder+ and wraps exceptions so callers always get an {AuthResult}.
          #
          # @return [Array(Object, nil)] +[payload, nil]+ on success
          # @return [Array(nil, Symbol)] +[nil, :decode_error]+ when the decoder raised
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
