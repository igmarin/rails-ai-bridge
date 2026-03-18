# frozen_string_literal: true

require "mcp"

module RailsAiContext
  # Rack middleware that intercepts requests at the configured HTTP path
  # and delegates to the MCP StreamableHTTPTransport. All other requests
  # pass through to the Rails app.
  class Middleware
    def initialize(app)
      @app = app
      @mcp_transport = nil
      @mutex = Mutex.new
    end

    def call(env)
      config = RailsAiContext.configuration
      path = config.http_path

      if env["PATH_INFO"] == path || env["PATH_INFO"] == "#{path}/"
        request = Rack::Request.new(env)
        transport.handle_request(request)
      else
        @app.call(env)
      end
    end

    private

    def transport
      @mutex.synchronize do
        @mcp_transport ||= begin
          server = Server.new(Rails.application, transport: :http).build
          MCP::Server::Transports::StreamableHTTPTransport.new(server)
        end
      end
    end
  end
end
