# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool that resolves an agent/workflow and returns it framed for adoption.
    #
    # The agent content is wrapped in an activation directive (intent header and a
    # follow-through footer requiring the workflow to be executed end to end) so
    # the assistant adopts the workflow rather than merely reading it.
    #
    # @example Adopt an agent workflow for the current task
    #   rails_use_agent name=tdd-workflow
    class UseAgent < BaseTool
      extend UsageFormatter

      tool_name 'rails_use_agent'
      description 'Load a named agent/workflow for adoption in the current task. Returns the full agent ' \
                  'content framed as an activation directive (follow the workflow end to end). ' \
                  'Use this when you intend to work within the agent\'s process now; use rails_resolve_skill ' \
                  'with type=agent for read-only inspection.'

      input_schema(
        properties: {
          name: {
            type: 'string',
            description: 'Name of the agent or workflow to adopt (e.g. "tdd-workflow").'
          }
        },
        required: ['name']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param name [String] agent name
      # @param _server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] activation directive or an error message
      def self.call(name:, _server_context: nil)
        resolver = Registry.build_resolver
        return text_response(format(UsageFormatter::NO_REGISTRY_MESSAGE, path: manifest_path)) unless resolver

        resolved = resolver.resolve_agent(name)
        return text_response(format(UsageFormatter::NOT_FOUND_AGENT_MESSAGE, name: name)) unless resolved

        text_response(format_usage(resolved, kind: :agent))
      end

      # @api private
      def self.manifest_path
        RailsAiBridge.configuration.registry.registry_manifest_path
      end
      private_class_method :manifest_path
    end
  end
end
