# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds MCP HTTP operational settings: rate limiting, structured logging,
    # post-auth authorization, and production boot guards.
    #
    # Access via +RailsAiBridge.configuration.mcp+.
    class Mcp
      # Controls when implicit HTTP rate limits apply.
      # +:dev+ — no implicit limit. +:production+ — implicit limit from {#security_profile}
      # in every environment. +:hybrid+ — implicit limit only when +Rails.env.production?+.
      # @return [Symbol]
      attr_accessor :mode

      # Default MCP HTTP rate ceiling per IP when {#rate_limit_max_requests} is +nil+.
      # +:strict+ 60, +:balanced+ 300, +:relaxed+ 1200 requests per {#rate_limit_window_seconds}.
      # @return [Symbol]
      attr_accessor :security_profile

      # Explicit requests allowed per {#rate_limit_window_seconds} per client IP.
      # +nil+ uses {#security_profile} defaults unless {#http_rate_limit_implicitly_suppressed?}.
      # +0+ or negative disables rate limiting entirely.
      # @return [Integer, String, nil]
      attr_reader :rate_limit_max_requests

      # Sets the rate limit max requests. Only Integer, numeric String (for ENV vars),
      # or nil are accepted. Non-numeric strings and other types raise ArgumentError.
      #
      # @param value [Integer, String, nil]
      # @raise [ArgumentError] when value is not Integer, numeric String, or nil
      # :reek:DuplicateMethodCall { allow_calls: ['raise_invalid_rate_limit'] }
      # :reek:NilCheck
      def rate_limit_max_requests=(value)
        case value
        when Integer
          @rate_limit_max_requests = value
        when nil
          @rate_limit_max_requests = nil
        when String
          raise_invalid_rate_limit(value) unless value.match?(/\A-?\d+\z/)

          @rate_limit_max_requests = value
        else
          raise_invalid_rate_limit(value)
        end
      end

      # Sliding window length for the rate limiter (seconds).
      # @return [Integer]
      attr_accessor :rate_limit_window_seconds

      # When +true+, MCP HTTP decisions emit one JSON line per response.
      # @return [Boolean]
      attr_accessor :http_log_json

      # Optional lambda called after successful auth: +->(context, request) { truthy }+.
      # Returning falsey yields HTTP 403.
      # @return [Proc, nil]
      attr_accessor :authorize

      # When +true+ in production, boot fails unless an MCP auth mechanism is configured.
      # @return [Boolean]
      attr_accessor :require_auth_in_production

      # When +true+, HTTP MCP requests receive +401+ unless a Bearer/JWT/static auth strategy is configured.
      # Off by default for backward compatibility (stdio and local dev HTTP).
      # @return [Boolean]
      attr_accessor :require_http_auth

      # Allowed origins for CORS on the HTTP MCP endpoint.
      # +nil+ or empty array disables CORS headers (default). Pass +['*']+ to allow any origin,
      # or a list of exact origins such as +['https://app.example.com']+.
      # @return [Array<String>, nil]
      attr_accessor :cors_origins

      # TTL in seconds for MCP tool result caching by argument fingerprint.
      # +0+ or negative disables caching. Default +0+ to keep existing behavior.
      # @return [Integer]
      attr_accessor :tool_result_cache_ttl

      def initialize
        @mode                     = :hybrid
        @security_profile         = :balanced
        @rate_limit_max_requests  = nil
        @rate_limit_window_seconds = 60
        @http_log_json            = false
        @authorize                = nil
        @require_auth_in_production = false
        @require_http_auth          = false
        @cors_origins             = nil
        @tool_result_cache_ttl    = 0
      end

      # @return [Boolean] whether tool call results should be cached
      def tool_result_cache_enabled?
        tool_result_cache_ttl.to_i.positive?
      end

      # Effective rate-limit ceiling for {HttpTransportApp} (+0+ means disabled).
      #
      # * Positive +rate_limit_max_requests+ — use that value.
      # * +0+ or negative — disable.
      # * +nil+ — use {#security_profile} unless {#http_rate_limit_implicitly_suppressed?}.
      #
      # @return [Integer]
      def effective_http_rate_limit_max_requests
        configured_value = @rate_limit_max_requests

        case configured_value
        when Integer
          return 0 if configured_value <= 0

          configured_value
        when nil
          return 0 if http_rate_limit_implicitly_suppressed?

          security_profile_rate_limit_max
        else
          n = configured_value.to_i
          return 0 if n <= 0

          n
        end
      end

      # Window length passed to {Mcp::HttpRateLimiter} (normalizes non-positive to 60).
      #
      # @return [Integer]
      def effective_http_rate_limit_window_seconds
        w = @rate_limit_window_seconds.to_i
        w <= 0 ? 60 : w
      end

      # @return [Boolean] +true+ when a +nil+ max should not inherit {#security_profile} defaults
      def http_rate_limit_implicitly_suppressed?
        case (@mode || :hybrid).to_sym
        when :dev        then true
        when :hybrid     then !Rails.env.production?
        else false
        end
      end

      private

      def security_profile_rate_limit_max
        { strict: 60, balanced: 300, relaxed: 1_200 }.fetch((@security_profile || :balanced).to_sym, 300)
      end

      def raise_invalid_rate_limit(value)
        raise ArgumentError,
              "rate_limit_max_requests must be Integer, numeric String, or nil, got: #{value.inspect}"
      end
    end
  end
end
