# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds MCP server transport and extensibility settings.
    class Server
      # @return [String] MCP server name advertised to clients
      attr_accessor :server_name

      # @return [String] MCP server version advertised to clients
      attr_accessor :server_version

      # @return [String] HTTP path for the MCP endpoint
      attr_accessor :http_path

      # @return [String] bind address for the standalone HTTP transport
      attr_accessor :http_bind

      # @return [Integer] port for the standalone HTTP transport
      attr_accessor :http_port

      # @return [Boolean] auto-mount MCP HTTP endpoint via Rack middleware
      attr_accessor :auto_mount

      # @return [Array<Class>] additional MCP tool classes appended to the built-in list
      attr_accessor :additional_tools

      # @return [Hash{String => Hash}] additional MCP resources merged with built-in resources
      attr_accessor :additional_resources

      def initialize
        @server_name        = "rails-ai-bridge"
        @server_version     = RailsAiBridge::VERSION
        @http_path          = "/mcp"
        @http_bind          = "127.0.0.1"
        @http_port          = 6029
        @auto_mount         = false
        @additional_tools   = []
        @additional_resources = {}
      end
    end
  end
end
