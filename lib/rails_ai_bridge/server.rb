# frozen_string_literal: true

require 'mcp'

module RailsAiBridge
  # Configures and starts an MCP server using the official Ruby SDK.
  # Registers all introspection tools and handles transport selection.
  # Supports both stdio and HTTP transports with proper error handling.
  class Server
    attr_reader :app, :transport_type

    # Transport type constants for type safety and consistency
    STDIO_TRANSPORT = :stdio
    HTTP_TRANSPORT = :http
    STREAMABLE_HTTP_TRANSPORT = :streamable_http

    # Log message templates for consistent logging
    STDIO_STARTUP_MESSAGE = '[rails-ai-bridge] MCP server started (stdio transport)'
    HTTP_STARTUP_MESSAGE = '[rails-ai-bridge] MCP server starting on %s:%s%s'
    TOOLS_LIST_MESSAGE = '[rails-ai-bridge] Tools: %s'

    # Error message template for unknown transport types
    UNKNOWN_TRANSPORT_ERROR = 'Unknown transport: %s. Use :stdio, :http, or :streamable_http'

    # Built-in MCP tools that are always available
    # These tools provide Rails application introspection capabilities
    TOOLS = [
      Tools::GetSchema,
      Tools::GetRoutes,
      Tools::GetModelDetails,
      Tools::GetGems,
      Tools::SearchCode,
      Tools::GetConventions,
      Tools::GetControllers,
      Tools::GetConfig,
      Tools::GetTestInfo,
      Tools::GetView,
      Tools::GetStimulus
    ].freeze

    # Initialize a new MCP server instance.
    # @param app [String, Object] Rails application instance or name
    # @param transport [Symbol] transport type (:stdio, :http, or :streamable_http)
    def initialize(app, transport: STDIO_TRANSPORT)
      @app = app
      @transport_type = transport
    end

    # Returns all available tool classes including additional configured tools.
    # @return [Array<Class>] list of tool classes
    def tool_classes
      TOOLS + RailsAiBridge.configuration.additional_tools
    end

    # Build and return the configured MCP::Server instance.
    # @return [MCP::Server] configured MCP server
    def build
      config = RailsAiBridge.configuration

      server = create_mcp_server(config)
      register_resources(server)
      server
    end

    # Start the MCP server with the configured transport.
    # @return [void]
    def start
      server = build

      case transport_type
      when STDIO_TRANSPORT
        start_stdio(server)
      when HTTP_TRANSPORT, STREAMABLE_HTTP_TRANSPORT
        start_http(server)
      else
        raise ConfigurationError, UNKNOWN_TRANSPORT_ERROR % transport_type
      end
    end

    private

    # Creates the MCP server with configuration and tools.
    # @param config [RailsAiBridge::Configuration] bridge configuration
    # @return [MCP::Server] created MCP server
    def create_mcp_server(config)
      MCP::Server.new(
        name: config.server_name,
        version: config.server_version,
        tools: tool_classes,
        resources: Resources.build_resources,
        resource_templates: Resources.build_templates
      )
    end

    # Registers resource handlers with the MCP server.
    # @param server [MCP::Server] the MCP server instance
    # @return [void]
    def register_resources(server)
      Resources.register(server)
    end

    def start_stdio(server)
      transport = create_stdio_transport(server)
      log_stdio_startup
      transport.open
    end

    def start_http(server)
      validate_http_server_in_production
      config = RailsAiBridge.configuration
      transport = create_http_transport(server)
      rack_app = build_rack_app(transport, config.http_path)

      log_http_startup(config)
      run_rack_server(rack_app, config)
    end

    # Creates stdio transport for the MCP server.
    # @param server [MCP::Server] the MCP server instance
    # @return [MCP::Server::Transports::StdioTransport] stdio transport
    def create_stdio_transport(server)
      MCP::Server::Transports::StdioTransport.new(server)
    end

    # Logs stdio transport startup and available tools.
    # @return [void]
    def log_stdio_startup
      warn STDIO_STARTUP_MESSAGE
      warn TOOLS_LIST_MESSAGE % tool_classes.map(&:tool_name).join(', ')
    end

    # Validates HTTP server usage in production environment.
    # @return [void]
    def validate_http_server_in_production
      RailsAiBridge.validate_http_mcp_server_in_production!
    end

    # Creates HTTP transport for the MCP server.
    # @param server [MCP::Server] the MCP server instance
    # @return [MCP::Server::Transports::StreamableHTTPTransport] HTTP transport
    def create_http_transport(server)
      MCP::Server::Transports::StreamableHTTPTransport.new(server)
    end

    # Logs HTTP server startup information.
    # @param config [RailsAiBridge::Configuration] bridge configuration
    # @return [void]
    def log_http_startup(config)
      warn format(HTTP_STARTUP_MESSAGE, config.http_bind, config.http_port, config.http_path)
      warn TOOLS_LIST_MESSAGE % tool_classes.map(&:tool_name).join(', ')
    end

    # Runs the Rack server with fallback for older Rack versions.
    # @param rack_app [Object] the Rack application
    # @param config [RailsAiBridge::Configuration] bridge configuration
    # @return [void]
    def run_rack_server(rack_app, config)
      require 'rackup'
      Rackup::Handler.default.run(rack_app, Host: config.http_bind, Port: config.http_port)
    rescue LoadError
      # Fallback for older rack without rackup gem
      require 'rack/handler'
      Rack::Handler.default.run(rack_app, Host: config.http_bind, Port: config.http_port)
    end

    # Builds a Rack application that delegates to the MCP transport.
    # @param transport [MCP::Server::Transports::StreamableHTTPTransport] HTTP transport
    # @param path [String] HTTP path for the MCP endpoint
    # @return [Object] Rack application
    def build_rack_app(transport, path)
      HttpTransportApp.build(transport: transport, path: path)
    end
  end
end
