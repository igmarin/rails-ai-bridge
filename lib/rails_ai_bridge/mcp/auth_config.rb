# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Nested auth options under {Settings#auth} / {#auth_configure}.
    class AuthConfig
      # @return [Symbol, nil] +:bearer_token+, +:static_bearer+, or +nil+ (auto)
      attr_accessor :strategy

      # @return [Proc, nil] +->(raw_bearer_token) { context_or_nil }+
      attr_accessor :token_resolver

      # @return [Proc, nil] +->(raw_bearer_string) { payload_or_nil }+ when using {Strategies::Jwt}
      attr_accessor :jwt_decoder
    end
  end
end
