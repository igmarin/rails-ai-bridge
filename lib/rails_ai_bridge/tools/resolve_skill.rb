# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool that resolves and returns the full content of a named skill or agent.
    #
    # Looks up the skill or agent in the loaded skill pack registry, following
    # priority ordering and deprecation redirects, and returns its complete
    # markdown content so AI assistants can read and apply the guidance directly
    # without falling back to rake tasks or file reads.
    #
    # @example Resolve a skill by name
    #   rails_resolve_skill name=code-review
    # @example Resolve from a specific pack
    #   rails_resolve_skill name=code-review pack=rails
    # @example Resolve an agent
    #   rails_resolve_skill name=tdd-workflow type=agent
    class ResolveSkill < BaseTool
      NOT_FOUND_MESSAGE = "Skill `%<name>s` not found in the loaded skill packs.\n\n" \
                          'Use `rails_list_registry type=skills` to see available skills.'
      NOT_FOUND_AGENT_MESSAGE = "Agent `%<name>s` not found in the loaded skill packs.\n\n" \
                                'Use `rails_list_registry type=agents` to see available agents.'
      NO_REGISTRY_MESSAGE = "No registry manifest found at `%<path>s`.\n\n" \
                            'Use `rails_list_registry type=skills` for setup instructions.'
      PACK_MISMATCH_MESSAGE = "Skill `%<name>s` was found in pack `%<actual>s`, not `%<requested>s`.\n\n" \
                              'Returning the skill from `%<actual>s`. Use `pack=` only to disambiguate ' \
                              'when the same skill name exists in multiple packs.'

      tool_name 'rails_resolve_skill'
      description 'Resolve and return the full content of a named skill or agent from the skill pack ' \
                  'registry. Use this after rails_list_registry to read a specific skill\'s guidance. ' \
                  'Follows priority ordering and deprecation redirects automatically. ' \
                  'Optional pack: pin resolution to a specific pack when the same name exists in multiple packs. ' \
                  'Optional type: "agent" to resolve a workflow/agent instead of a skill (default: "skill").'

      input_schema(
        properties: {
          name: {
            type: 'string',
            description: 'Name of the skill or agent to resolve (e.g. "code-review", "tdd-workflow").'
          },
          pack: {
            type: 'string',
            description: 'Optional pack name to pin resolution to (e.g. "rails", "core"). ' \
                         'When omitted, the highest-priority match across all loaded packs is returned.'
          },
          type: {
            type: 'string',
            enum: %w[skill agent],
            description: 'What to resolve: "skill" (default) or "agent".'
          }
        },
        required: ['name']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param name [String] skill or agent name
      # @param pack [String, nil] optional pack name filter
      # @param type [String] "skill" or "agent" (default: "skill")
      # @param _server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] full skill/agent content or an error message
      def self.call(name:, pack: nil, type: 'skill', _server_context: nil)
        resolver = Registry.build_resolver
        return text_response(format(NO_REGISTRY_MESSAGE, path: manifest_path)) unless resolver

        resolved = resolve(resolver, name: name, pack: pack, type: type)
        return text_response(not_found_message(name, type)) unless resolved

        text_response(format_response(resolved, requested_pack: pack))
      end

      # @api private
      def self.manifest_path
        RailsAiBridge.configuration.registry.registry_manifest_path
      end
      private_class_method :manifest_path

      # @api private
      def self.resolve(resolver, name:, pack:, type:)
        if pack
          # Pack-pinned resolution: find all matches and select the one from the requested pack
          all = type == 'agent' ? resolver.list_agents : resolver.list_skills
          return nil unless all.any? { |s| s.name == name }

          # Re-resolve using the resolver to get content — try pack-specific lookup
          resolver.active_packs
                  .select { |p| p.name == pack }
                  .each do |loaded_pack|
            method = type == 'agent' ? :resolve_agent : :resolve_skill
            candidate = single_pack_resolver(loaded_pack).public_send(method, name)
            return candidate if candidate
          end

          # Fall back to priority-based resolution if pack filter found nothing
          type == 'agent' ? resolver.resolve_agent(name) : resolver.resolve_skill(name)
        else
          type == 'agent' ? resolver.resolve_agent(name) : resolver.resolve_skill(name)
        end
      end
      private_class_method :resolve

      # Builds a temporary single-pack resolver for pack-pinned lookups.
      # @api private
      def self.single_pack_resolver(loaded_pack)
        Registry::Resolver.new([loaded_pack])
      end
      private_class_method :single_pack_resolver

      # @api private
      def self.not_found_message(name, type)
        template = type == 'agent' ? NOT_FOUND_AGENT_MESSAGE : NOT_FOUND_MESSAGE
        format(template, name: name)
      end
      private_class_method :not_found_message

      # @api private
      def self.format_response(resolved, requested_pack:)
        header = []
        header << "# #{resolved.name}"
        header << "_Pack: **#{resolved.pack}**_"

        if requested_pack && resolved.pack != requested_pack
          header << ''
          header << format(PACK_MISMATCH_MESSAGE, name: resolved.name, actual: resolved.pack, requested: requested_pack)
        end

        header << ''
        header << resolved.content

        header.join("\n")
      end
      private_class_method :format_response
    end
  end
end
