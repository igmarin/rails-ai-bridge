# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # MCP HTTP settings under {RailsAiBridge::Configuration#mcp}.
    class Settings
      # @return [Symbol] +:dev+, +:production+, +:hybrid+ (documentational)
      attr_accessor :mode

      # @return [Symbol] +:strict+, +:balanced+, +:relaxed+
      attr_accessor :security_profile

      # When +true+ in production, boot fails unless {RailsAiBridge.mcp_auth_mechanism_configured?}.
      # @return [Boolean]
      attr_accessor :require_auth_in_production

      # Max MCP HTTP requests per +rate_limit_window_seconds+ per client IP, in-process (+nil+ or +0+ disables).
      # @return [Integer, nil]
      attr_accessor :rate_limit_max_requests

      # Sliding window for {rate_limit_max_requests} (seconds).
      # @return [Integer]
      attr_accessor :rate_limit_window_seconds

      # @return [Proc, nil] +->(context, request) { truthy }+ after successful authentication
      attr_accessor :authorize

      # @return [AuthConfig]
      attr_reader :auth

      def initialize
        @auth = AuthConfig.new
        @mode = :hybrid
        @security_profile = :balanced
        @require_auth_in_production = false
        @rate_limit_max_requests = nil
        @rate_limit_window_seconds = 60
        @authorize = nil
      end

      # @yieldparam auth [AuthConfig]
      # @return [AuthConfig]
      def auth_configure
        yield @auth if block_given?
        @auth
      end
    end
  end
end
