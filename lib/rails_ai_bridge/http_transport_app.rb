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
        lambda do |env|
          unless env["PATH_INFO"] == path || env["PATH_INFO"] == "#{path}/"
            return [ 404, { "Content-Type" => "application/json" }, [ '{"error":"Not found"}' ] ]
          end

          request = Rack::Request.new(env)
          unless McpHttpAuth.authorized_request?(request)
            return McpHttpAuth.unauthorized_rack_response
          end

          transport.handle_request(request)
        end
      end
    end
  end
end
