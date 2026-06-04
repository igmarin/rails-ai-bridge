# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for listing all available skills across loaded packs.
    class RailsListSkills < BaseTool
      tool_name 'rails_list_skills'
      description 'List all available skills across loaded skill packs, with descriptions and source pack information.'

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] markdown list of skills or an error message
      def self.call(_server_context: nil)
        resolver = registry_resolver
        return text_response('Registry resolution not available. Configure registry settings in config/registry.') unless resolver

        skills = resolver.list_skills
        return text_response('No skills available') if skills.empty?

        formatter = ResponseFormatter.new(skills)
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
      # Formats skill summaries as markdown for {RailsListSkills}.
      class ResponseFormatter
        def initialize(skills)
          @skills = skills
        end

        def format
          lines = ['# Available Skills', '']
          @skills.each do |skill|
            lines << "- **#{skill.name}** (from #{skill.pack})"
            lines << "  #{skill.description}"
            lines << ''
          end
          lines.join("\n")
        end
      end
    end
  end
end
