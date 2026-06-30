# frozen_string_literal: true

module RailsAiBridge
  # Builds the Rack endpoint used by both standalone HTTP mode and the
  # middleware auto-mount path so request handling stays in one place.
  class HttpTransportApp
    class << self
      # @param transport [MCP::Server::Transports::StreamableHTTPTransport] transport to delegate to
      # @param path [String] configured MCP endpoint path
      # @return [Proc] rack-compatible app
      def build(transport:, path:)
        mcp_cfg    = RailsAiBridge.configuration.mcp
        max_reqs   = mcp_cfg.effective_http_rate_limit_max_requests
        window_sec = mcp_cfg.effective_http_rate_limit_window_seconds
        limiter    = mcp_cfg.rate_limiter || build_default_rate_limiter(max_requests: max_reqs,
                                                                        window_seconds: window_sec)
        cors_origins = Array(mcp_cfg.cors_origins).reject(&:empty?)

        lambda do |env|
          return [404, { 'Content-Type' => 'application/json' }, ['{"error":"Not found"}']] unless [path, "#{path}/"].include?(env['PATH_INFO'])

          request = Rack::Request.new(env)
          cors_headers = build_cors_headers(request.get_header('HTTP_ORIGIN'), cors_origins)

          return [204, cors_headers, ['']] if request.request_method == 'OPTIONS' && cors_headers

          if mcp_cfg.require_http_auth && !Mcp::Authenticator.any_configured?
            Mcp::HttpStructuredLog.emit(request: request, event: :unauthorized, http_status: 401)
            return Mcp::Authenticator.unauthorized_rack_response
          end

          auth_result = Mcp::Authenticator.call(request)
          unless auth_result.success?
            Mcp::HttpStructuredLog.emit(request: request, event: :unauthorized, http_status: 401)
            return Mcp::Authenticator.unauthorized_rack_response
          end

          authorize = RailsAiBridge.configuration.mcp.authorize
          if authorize
            begin
              authorized = authorize.call(auth_result.context, request)
            rescue StandardError => error
              Rails.logger.error("rails_ai_bridge: authorize lambda raised #{error.class}: #{error.message}") if defined?(Rails) && Rails.logger
              Mcp::HttpStructuredLog.emit(request: request, event: :forbidden, http_status: 403)
              return [403, { 'Content-Type' => 'application/json' }, ['{"error":"Forbidden"}']]
            end

            unless authorized
              Rails.logger.warn("rails_ai_bridge: authorize lambda denied access for #{request.ip} at #{request.path}") if defined?(Rails) && Rails.logger
              Mcp::HttpStructuredLog.emit(request: request, event: :forbidden, http_status: 403)
              return [403, { 'Content-Type' => 'application/json' }, ['{"error":"Forbidden"}']]
            end
          end

          if limiter && !rate_limiter_allow?(limiter, request)
            Mcp::HttpStructuredLog.emit(request: request, event: :rate_limited, http_status: 429)
            return [429, { 'Content-Type' => 'application/json', 'Retry-After' => window_sec.to_s },
                    ['{"error":"Too many requests"}']]
          end

          response = transport.handle_request(request)
          Mcp::HttpStructuredLog.emit(request: request, event: :handled, http_status: response.first)
          response[1].merge!(cors_headers) if cors_headers
          response
        end
      end

      private

      def build_default_rate_limiter(max_requests:, window_seconds:)
        return nil unless max_requests.positive?

        Mcp::HttpRateLimiter.new(max_requests: max_requests, window_seconds: window_seconds)
      end

      # Asks a configured rate limiter whether a request may proceed.
      # Supports objects that expose +allow?(ip)+ (preferred) or +call(ip)+.
      #
      # @param limiter [#allow?, #call]
      # @param request [Rack::Request]
      # @return [Boolean]
      def rate_limiter_allow?(limiter, request)
        if limiter.respond_to?(:allow?)
          limiter.allow?(request.ip)
        elsif limiter.respond_to?(:call)
          limiter.call(request.ip)
        else
          true
        end
      end

      # Builds CORS response headers when the request origin is allowed.
      #
      # @param origin [String, nil] value of the Origin header
      # @param cors_origins [Array<String>] configured allowed origins
      # @return [Hash{String => String}, nil] headers to add, or +nil+ when CORS is disabled/unmatched
      def build_cors_headers(origin, cors_origins)
        return nil if cors_origins.empty?
        return nil if origin.blank?
        return nil unless cors_origins.include?('*') || cors_origins.include?(origin)

        {
          'Access-Control-Allow-Origin' => origin,
          'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers' => 'Authorization, Content-Type'
        }
      end
    end
  end
end
