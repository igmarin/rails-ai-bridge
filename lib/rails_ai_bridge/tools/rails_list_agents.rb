# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for listing all available agents across loaded packs.
    class RailsListAgents < BaseTool
      tool_name 'rails_list_agents'
      description 'List all available agents across loaded skill packs, with descriptions and source pack information.'

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] markdown list of agents or an error message
      def self.call(_server_context: nil)
        resolver = registry_resolver
        return text_response('Registry resolution not available. Configure registry settings in config/registry.') unless resolver

        agents = resolver.list_agents
        return text_response('No agents available') if agents.empty?

        formatter = ResponseFormatter.new(agents)
        text_response(formatter.format)
      end

      # Builds a registry resolver from the current configuration.
      #
      # @return [Registry::Resolver, nil] resolver instance or nil if configuration is invalid
      def self.registry_resolver
        extend Registry::ResolverBuilder

        build_resolver(config)
      end

      # @private
      # Formats agent summaries as markdown for {RailsListAgents}.
      class ResponseFormatter
        def initialize(agents)
          @agents = agents
        end

        def format
          lines = ['# Available Agents', '']
          @agents.each do |agent|
            lines << "- **#{agent.name}** (from #{agent.pack})"
            lines << "  #{agent.description}"
            lines << ''
          end
          lines.join("\n")
        end
      end
    end
  end
end
