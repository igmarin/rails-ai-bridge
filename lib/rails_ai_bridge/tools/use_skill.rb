# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool that resolves a skill and returns it framed for immediate application.
    #
    # Whereas +rails_resolve_skill+ returns content for inspection, this tool wraps
    # the resolved skill in an application directive (intent header, deprecation
    # notice when redirected, follow-through footer) so the assistant treats it as
    # instructions to execute rather than reference material to read.
    #
    # @example Apply a skill to the current task
    #   rails_use_skill name=code-review
    class UseSkill < BaseTool
      extend UsageFormatter

      tool_name 'rails_use_skill'
      description 'Load a named skill for immediate application to the current task. Returns the full ' \
                  'skill content framed as an application directive (work through it step by step). ' \
                  'Use this when you intend to act on the skill now; use rails_resolve_skill for ' \
                  'read-only inspection or pack-pinned lookups.'

      input_schema(
        properties: {
          name: {
            type: 'string',
            description: 'Name of the skill to apply (e.g. "code-review").'
          }
        },
        required: ['name']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param name [String] skill name
      # @param _server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] application directive or an error message
      # :reek:TooManyStatements -- linear tool flow: resolver, resolve, deprecation, render
      def self.call(name:, _server_context: nil)
        resolver = Registry.build_resolver
        return text_response(format(UsageFormatter::NO_REGISTRY_MESSAGE, path: manifest_path)) unless resolver

        resolved = resolver.resolve_skill(name)
        return text_response(format(UsageFormatter::NOT_FOUND_SKILL_MESSAGE, name: name)) unless resolved

        warning = resolver.check_deprecated(name)
        text_response(format_usage(resolved, kind: :skill, deprecation_warning: warning))
      end

      # @api private
      def self.manifest_path
        RailsAiBridge.configuration.registry.registry_manifest_path
      end
      private_class_method :manifest_path
    end
  end
end
