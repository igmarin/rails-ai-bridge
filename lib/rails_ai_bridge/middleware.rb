# frozen_string_literal: true

require 'mcp'

module RailsAiBridge
  # Rack middleware that intercepts requests at the configured HTTP path
  # and delegates to the MCP StreamableHTTPTransport. All other requests
  # pass through to the Rails app.
  class Middleware
    def initialize(app)
      @app = app
      @transport = nil
      @mutex = Mutex.new
    end

    def call(env)
      config = RailsAiBridge.configuration
      path = config.http_path

      if [path, "#{path}/"].include?(env['PATH_INFO'])
        rack_app.call(env)
      else
        @app.call(env)
      end
    end

    private

    # The transport is memoized because it is expensive to create and bound to
    # the process-wide application. In Rails-hosted mode, AppScope.current_app
    # always resolves to Rails.application. In standalone mode, the CLI sets
    # the scope before starting the server, so the first resolution is correct
    # for the process lifetime.
    def transport
      @mutex.synchronize do
        @transport ||= begin
          server = Server.new(AppScope.current_app, transport: :http).build
          MCP::Server::Transports::StreamableHTTPTransport.new(server)
        end
      end
    end

    def rack_app
      @rack_app ||= HttpTransportApp.build(transport: transport, path: RailsAiBridge.configuration.http_path)
    end
  end
end
