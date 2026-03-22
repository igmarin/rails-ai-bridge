# frozen_string_literal: true

require "mcp"

module RailsAiBridge
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
      config = RailsAiBridge.configuration
      path = config.http_path

      if env["PATH_INFO"] == path || env["PATH_INFO"] == "#{path}/"
        rack_app.call(env)
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

    def rack_app
      @rack_app ||= HttpTransportApp.build(transport: transport, path: RailsAiBridge.configuration.http_path)
    end
  end
end
