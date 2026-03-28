# frozen_string_literal: true

module RailsAiBridge
  # Builds the Rack endpoint used by both standalone HTTP mode and the
  # middleware auto-mount path so request handling stays in one place.
  class HttpTransportApp
    class << self
      # Returns a Rack app for the MCP HTTP path: optional per-IP rate limit, Bearer auth,
      # optional +authorize+, then the streamable transport. Limit values are read from
      # {RailsAiBridge::Configuration#mcp} at call time of +build+ (not on each request).
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
            return McpHttpAuth.rate_limited_rack_response(retry_after: retry_after)
          end

          unless McpHttpAuth.authorized_request?(request)
            return McpHttpAuth.unauthorized_rack_response
          end

          authz = RailsAiBridge.configuration.mcp.authorize
          if authz
            ctx = request.env[Mcp::HttpAuth::ENV_CONTEXT_KEY]
            unless authz.call(ctx, request)
              return McpHttpAuth.forbidden_rack_response
            end
          end

          transport.handle_request(request)
        end
      end

      private

      # @param mcp [RailsAiBridge::Mcp::Settings]
      # @return [Array(RailsAiBridge::Mcp::HttpRateLimiter, Integer, nil), Array(nil, nil)]
      def build_rate_limit(mcp)
        max = mcp.rate_limit_max_requests.to_i
        return [ nil, nil ] if max <= 0

        window = mcp.rate_limit_window_seconds.to_i
        window = 60 if window <= 0

        limiter = Mcp::HttpRateLimiter.new(max_requests: max, window_seconds: window)
        [ limiter, window ]
      end
    end
  end
end
