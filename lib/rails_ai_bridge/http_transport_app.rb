# frozen_string_literal: true

module RailsAiBridge
  # Builds the Rack endpoint used by both standalone HTTP mode and the
  # middleware auto-mount path so request handling stays in one place.
  class HttpTransportApp
    class << self
      # Returns a Rack app for the MCP HTTP path: optional per-IP rate limit, Bearer auth,
      # optional +authorize+, then the streamable transport. Rate-limit ceilings and window
      # are fixed at +build+ from {RailsAiBridge::Mcp::Settings#effective_http_rate_limit_max_requests}
      # and {#effective_http_rate_limit_window_seconds}. JSON access logging (+http_log_json+) is
      # evaluated on each request inside {Mcp::HttpStructuredLog.emit}.
      #
      # @param transport [MCP::Server::Transports::StreamableHTTPTransport] transport to delegate to
      # @param path [String] configured MCP endpoint path
      # @return [Proc] rack-compatible app
      def build(transport:, path:)
        mcp = RailsAiBridge.configuration.mcp
        limiter, retry_after = build_rate_limit(mcp)

        lambda do |env|
          unless env["PATH_INFO"] == path || env["PATH_INFO"] == "#{path}/"
            return [ 404, { "Content-Type" => "application/json" }, [ '{"error":"Not found"}' ] ]
          end

          request = Rack::Request.new(env)
          if limiter && !limiter.allow?(request.ip)
            Mcp::HttpStructuredLog.emit(request: request, event: :rate_limited, http_status: 429)
            return McpHttpAuth.rate_limited_rack_response(retry_after: retry_after)
          end

          unless McpHttpAuth.authorized_request?(request)
            Mcp::HttpStructuredLog.emit(request: request, event: :unauthorized, http_status: 401)
            return McpHttpAuth.unauthorized_rack_response
          end

          authz = RailsAiBridge.configuration.mcp.authorize
          if authz
            ctx = request.env[Mcp::HttpAuth::ENV_CONTEXT_KEY]
            unless authz.call(ctx, request)
              Mcp::HttpStructuredLog.emit(request: request, event: :forbidden, http_status: 403)
              return McpHttpAuth.forbidden_rack_response
            end
          end

          status, headers, body = transport.handle_request(request)
          Mcp::HttpStructuredLog.emit(request: request, event: :handled, http_status: status)
          [ status, headers, body ]
        end
      end

      private

      # @param mcp [RailsAiBridge::Mcp::Settings]
      # @return [Array(RailsAiBridge::Mcp::HttpRateLimiter, Integer, nil), Array(nil, nil)]
      def build_rate_limit(mcp)
        max = mcp.effective_http_rate_limit_max_requests
        return [ nil, nil ] if max <= 0

        window = mcp.effective_http_rate_limit_window_seconds
        limiter = Mcp::HttpRateLimiter.new(max_requests: max, window_seconds: window)
        [ limiter, window ]
      end
    end
  end
end
