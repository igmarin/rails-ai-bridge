# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # MCP HTTP settings under {RailsAiBridge::Configuration#mcp}.
    class Settings
      # Controls when implicit HTTP rate limits apply (see {#effective_http_rate_limit_max_requests}).
      # +:dev+ — no implicit limit (+nil+ max). +:production+ — implicit limit from {#security_profile}.
      # +:hybrid+ — implicit limit only when +Rails.env.production?+.
      # @return [Symbol]
      attr_accessor :mode

      # Default MCP HTTP rate ceiling per IP when +rate_limit_max_requests+ is +nil+ (see {#effective_http_rate_limit_max_requests}).
      # +:strict+ 60, +:balanced+ 300, +:relaxed+ 1200 requests per +rate_limit_window_seconds+ sliding window (default +60+ seconds).
      # @return [Symbol]
      attr_accessor :security_profile

      # When +true+ in production, boot fails unless {RailsAiBridge.mcp_auth_mechanism_configured?}.
      # @return [Boolean]
      attr_accessor :require_auth_in_production

      # Explicit MCP HTTP requests allowed per {#rate_limit_window_seconds} per client IP (+Integer+ or numeric string).
      # +nil+ uses {#security_profile} defaults unless {#http_rate_limit_implicitly_suppressed?}; +0+ disables limiting.
      # @return [Integer, nil, String]
      attr_accessor :rate_limit_max_requests

      # Sliding window for {rate_limit_max_requests} (seconds).
      # @return [Integer]
      attr_accessor :rate_limit_window_seconds

      # @return [Proc, nil] +->(context, request) { truthy }+ after successful authentication
      attr_accessor :authorize

      # When +true+, MCP HTTP decisions emit one JSON line per response (+msg+ +rails_ai_bridge.mcp.http+).
      # @return [Boolean]
      attr_accessor :http_log_json

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
        @http_log_json = false
      end

      # Effective rate-limit ceiling for {HttpTransportApp} (+0+ means disabled).
      #
      # * Positive +rate_limit_max_requests+ — use that value (+Integer+ or numeric string).
      # * +0+ — disable (even if {#security_profile} would suggest a limit).
      # * +nil+ — use {#security_profile} unless {#http_rate_limit_implicitly_suppressed?}.
      #
      # @return [Integer]
      def effective_http_rate_limit_max_requests
        raw = @rate_limit_max_requests

        case raw
        when Integer
          return 0 if raw <= 0

          raw
        when nil
          return 0 if http_rate_limit_implicitly_suppressed?

          security_profile_rate_limit_max
        else
          n = raw.to_i
          return 0 if n <= 0

          n
        end
      end

      # Window length passed to {HttpRateLimiter} (+<= 0+ normalizes to +60+).
      #
      # @return [Integer]
      def effective_http_rate_limit_window_seconds
        w = @rate_limit_window_seconds.to_i
        w = 60 if w <= 0

        w
      end

      # @return [Boolean] +true+ when +nil+ max should not inherit {#security_profile} defaults
      def http_rate_limit_implicitly_suppressed?
        case (@mode || :hybrid).to_sym
        when :dev
          true
        when :hybrid
          !Rails.env.production?
        when :production
          false
        else
          false
        end
      end

      # @yieldparam auth [AuthConfig]
      # @return [AuthConfig]
      def auth_configure
        yield @auth if block_given?
        @auth
      end

      private

      def security_profile_rate_limit_max
        case (@security_profile || :balanced).to_sym
        when :strict then 60
        when :balanced then 300
        when :relaxed then 1_200
        else
          300
        end
      end
    end
  end
end
