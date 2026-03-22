# frozen_string_literal: true

require "mcp"

module RailsAiBridge
  # Configures and starts an MCP server using the official Ruby SDK.
  # Registers all introspection tools and handles transport selection.
  class Server
    attr_reader :app, :transport_type

    TOOLS = [
      Tools::GetSchema,
      Tools::GetRoutes,
      Tools::GetModelDetails,
      Tools::GetGems,
      Tools::SearchCode,
      Tools::GetConventions,
      Tools::GetControllers,
      Tools::GetConfig,
      Tools::GetTestInfo
    ].freeze

    def initialize(app, transport: :stdio)
      @app = app
      @transport_type = transport
    end

    def tool_classes
      TOOLS + RailsAiBridge.configuration.additional_tools
    end

    # Build and return the configured MCP::Server instance
    def build
      config = RailsAiBridge.configuration

      server = MCP::Server.new(
        name: config.server_name,
        version: config.server_version,
        tools: tool_classes
      )

      Resources.register(server)

      server
    end

    # Start the MCP server with the configured transport
    def start
      server = build

      case transport_type
      when :stdio
        start_stdio(server)
      when :http, :streamable_http
        start_http(server)
      else
        raise ConfigurationError, "Unknown transport: #{transport_type}. Use :stdio or :http"
      end
    end

    private

    def start_stdio(server)
      transport = MCP::Server::Transports::StdioTransport.new(server)
      # Log to stderr so we don't pollute the JSON-RPC channel on stdout
      $stderr.puts "[rails-ai-bridge] MCP server started (stdio transport)"
      $stderr.puts "[rails-ai-bridge] Tools: #{tool_classes.map { |t| t.tool_name }.join(', ')}"
      transport.open
    end

    def start_http(server)
      RailsAiBridge.validate_http_mcp_server_in_production!

      config = RailsAiBridge.configuration
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server)

      # Build a minimal Rack app that delegates to the MCP transport
      rack_app = build_rack_app(transport, config.http_path)

      $stderr.puts "[rails-ai-bridge] MCP server starting on #{config.http_bind}:#{config.http_port}#{config.http_path}"
      $stderr.puts "[rails-ai-bridge] Tools: #{tool_classes.map { |t| t.tool_name }.join(', ')}"

      require "rackup"
      Rackup::Handler.default.run(rack_app, Host: config.http_bind, Port: config.http_port)
    rescue LoadError
      # Fallback for older rack without rackup gem
      require "rack/handler"
      Rack::Handler.default.run(rack_app, Host: config.http_bind, Port: config.http_port)
    end

    def build_rack_app(transport, path)
      HttpTransportApp.build(transport: transport, path: path)
    end
  end
end
