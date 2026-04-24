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
        limiter    = if max_reqs.positive?
                       Mcp::HttpRateLimiter.new(max_requests: max_reqs,
                                                window_seconds: window_sec)
                     end

        lambda do |env|
          return [404, { 'Content-Type' => 'application/json' }, ['{"error":"Not found"}']] unless [path, "#{path}/"].include?(env['PATH_INFO'])

          request = Rack::Request.new(env)

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
            authorized = begin
              authorize.call(auth_result.context, request)
            rescue StandardError => e
              Rails.logger.error("rails_ai_bridge: authorize lambda raised #{e.class}: #{e.message}") if defined?(Rails)
              false
            end
            unless authorized
              Mcp::HttpStructuredLog.emit(request: request, event: :forbidden, http_status: 403)
              return [403, { 'Content-Type' => 'application/json' }, ['{"error":"Forbidden"}']]
            end
          end

          if limiter && !limiter.allow?(request.ip)
            Mcp::HttpStructuredLog.emit(request: request, event: :rate_limited, http_status: 429)
            return [429, { 'Content-Type' => 'application/json', 'Retry-After' => window_sec.to_s },
                    ['{"error":"Too many requests"}']]
          end

          response = transport.handle_request(request)
          Mcp::HttpStructuredLog.emit(request: request, event: :handled, http_status: response.first)
          response
        end
      end
    end
  end
end
