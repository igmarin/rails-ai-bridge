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
      @rack_app = nil
      @monitor = Monitor.new
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
      @monitor.synchronize do
        @transport ||= begin
          server = Server.new(AppScope.current_app, transport: :http).build
          MCP::Server::Transports::StreamableHTTPTransport.new(server)
        end
      end
    end

    # Built under the same (reentrant) monitor as +transport+ — the builder
    # itself resolves the transport — so concurrent first requests cannot
    # create two apps (and two rate limiters) with one discarded.
    def rack_app
      @monitor.synchronize do
        @rack_app ||= HttpTransportApp.build(transport: transport, path: RailsAiBridge.configuration.http_path)
      end
    end
  end
end
