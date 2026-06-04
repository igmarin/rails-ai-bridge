# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for listing all loaded packs with their priorities.
    class RailsListPacks < BaseTool
      tool_name 'rails_list_packs'
      description 'List all loaded skill packs with their priority levels and base paths.'

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] markdown list of packs or an error message
      def self.call(_server_context: nil)
        resolver = registry_resolver
        return text_response('Registry resolution not available. Configure registry settings in config/registry.') unless resolver

        packs = resolver.active_packs
        return text_response('No packs loaded') if packs.empty?

        formatter = ResponseFormatter.new(packs)
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
      # Formats loaded packs as markdown for {RailsListPacks}.
      class ResponseFormatter
        def initialize(packs)
          @packs = packs
        end

        def format
          lines = ['# Loaded Packs', '']
          sorted_packs = @packs.sort_by(&:priority)
          sorted_packs.each do |pack|
            lines << "- **#{pack.name}** (priority: #{pack.priority})"
            lines << "  Base path: #{pack.base_path}"
            lines << ''
          end
          lines.join("\n")
        end
      end
    end
  end
end
