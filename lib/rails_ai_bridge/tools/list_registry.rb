# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for querying the skill pack registry catalog.
    #
    # A single entry point replacing the previous +rails_list_skills+,
    # +rails_list_agents+, and +rails_list_packs+ tools. The required +type+
    # parameter routes to the appropriate catalog view:
    #
    # - <tt>type: "skills"</tt>   — all available skills across loaded packs
    # - <tt>type: "agents"</tt>   — all available agents/workflows
    # - <tt>type: "packs"</tt>    — loaded packs with version, priority, and summary
    #
    # @example List all skills
    #   rails_list_registry type=skills
    # @example Filter skills by pack
    #   rails_list_registry type=skills pack=rails
    # @example List active packs
    #   rails_list_registry type=packs
    class ListRegistry < BaseTool
      DESCRIPTION_MAX_LENGTH = 80
      SETUP_DOC_PATH = 'docs/skill-registry-guide.md'

      SETUP_MESSAGE = <<~MSG.freeze
        No registry manifest found at `%<path>s`.

        To use skill registry tools, create a registry manifest file.
        See `#{SETUP_DOC_PATH}` for a step-by-step guide.

        Quick start — add `config/rails_ai_bridge_registry.json` to your Rails app:

        ```json
        {
          "version": "1.0.0",
          "packs": {},
          "default_stack": []
        }
        ```

        Then configure the registry in `config/initializers/rails_ai_bridge.rb`:

        ```ruby
        RailsAiBridge.configure do |config|
          config.registry.registry_manifest_path = "config/rails_ai_bridge_registry.json"
        end
        ```

        Once configured, add packs and run `rails ai:skills:list` to verify.
      MSG

      UNKNOWN_TYPE_MESSAGE = 'Unknown type `%<type>s`. Valid values: "skills", "agents", "packs".'

      tool_name 'rails_list_registry'
      description 'Query the skill pack registry catalog. ' \
                  'Use type=skills to list available skills, type=agents for workflows, ' \
                  'type=packs to see loaded packs with version and priority. ' \
                  'Optional pack: filter narrows skills/agents to one pack. ' \
                  'Requires config/rails_ai_bridge_registry.json — see docs/skill-registry-guide.md.'

      input_schema(
        properties: {
          type: {
            type: 'string',
            enum: %w[skills agents packs],
            description: 'What to list: "skills", "agents", or "packs".'
          },
          pack: {
            type: 'string',
            description: 'Filter skills or agents by pack name (e.g. "rails", "core"). ' \
                         'Ignored when type is "packs".'
          }
        },
        required: ['type']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param type [String] "skills", "agents", or "packs"
      # @param pack [String, nil] optional pack name filter (skills/agents only)
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] formatted catalog or a setup/error message
      def self.call(type:, pack: nil, _server_context: nil)
        return text_response(format(UNKNOWN_TYPE_MESSAGE, type: type)) unless %w[skills agents packs].include?(type)

        resolver = Registry.build_resolver
        return text_response(format(SETUP_MESSAGE, path: manifest_path)) unless resolver

        text_response(RegistryCatalogFormatter.new(resolver, type: type, pack_filter: pack).format)
      end

      # @api private
      def self.manifest_path
        RailsAiBridge.configuration.registry.registry_manifest_path
      end
      private_class_method :manifest_path

      # Formats the registry catalog as markdown for a given type.
      #
      # Single responsibility: converts resolver data into display-ready markdown.
      # Does not know about MCP, tools, or configuration.
      #
      # @api private
      class RegistryCatalogFormatter
        # @param resolver [Registry::Resolver]
        # @param type [String] "skills", "agents", or "packs"
        # @param pack_filter [String, nil]
        def initialize(resolver, type:, pack_filter: nil)
          @resolver    = resolver
          @type        = type
          @pack_filter = pack_filter
        end

        # @return [String] markdown string
        def format
          case @type
          when 'skills'  then format_catalog(@resolver.list_skills,   noun: 'Skill')
          when 'agents'  then format_catalog(@resolver.list_agents,   noun: 'Agent')
          when 'packs'   then format_packs(@resolver.active_packs)
          end
        end

        private

        def format_catalog(items, noun:)
          items = items.select { |i| i.pack == @pack_filter } if @pack_filter
          return empty_catalog_message(noun) if items.empty?

          lines = ["# Available #{noun}s (#{items.length})", '']
          lines << "| #{noun} | Pack | Description |"
          lines << '|--------|------|-------------|'
          items.each do |item|
            lines << "| `#{item.name}` | #{item.pack} | #{truncate(item.description)} |"
          end
          lines.join("\n")
        end

        def format_packs(packs)
          return 'No packs are currently loaded. Check your registry manifest configuration.' if packs.empty?

          lines = ["# Active Skill Packs (#{packs.length})", '']
          lines << '| Pack | Version | Priority | Summary |'
          lines << '|------|---------|----------|---------|'
          packs.each do |pack|
            summary = truncate(pack.tile.summary || 'No summary.')
            lines << "| **#{pack.name}** | #{pack.tile.version} | #{pack.priority} | #{summary} |"
          end
          lines << ''
          lines << '_Priority: 0 = local (highest), 10 = rails/hanami, 20 = core, 30 = other (lowest)._'
          lines.join("\n")
        end

        def empty_catalog_message(noun)
          if @pack_filter
            "No #{noun.downcase}s found for pack `#{@pack_filter}`. " \
              'Use `rails_list_registry type=packs` to see loaded packs.'
          else
            "No #{noun.downcase}s are loaded. Check your registry manifest configuration."
          end
        end

        def truncate(text)
          return text if text.length <= DESCRIPTION_MAX_LENGTH

          "#{text[0, DESCRIPTION_MAX_LENGTH - 1]}…"
        end
      end
    end
  end
end
