# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates OpenAI Codex project guidance as Markdown suitable for +AGENTS.md+.
      #
      # In +:compact+ mode (default), output is bounded and MCP-focused. In +:full+ mode,
      # delegates to {MarkdownSerializer} with Codex-oriented header and footer formatters injected
      # via constructor arguments.
      #
      # @since 0.8.0
      class CodexSerializer < BaseProviderSerializer
        # @param context [Hash] Introspection hash from {Introspector#call} (e.g. +:app_name+, +:schema+, +:models+).
        # @param config [RailsAiBridge::Configuration] Bridge configuration (+context_mode+, limits, etc.).
        def initialize(context, config: RailsAiBridge.configuration)
          super
        end

        # @return [String] Markdown written to `AGENTS.md` by {ContextFileSerializer}.
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
                                   header_class: Formatters::Providers::CodexHeaderFormatter,
                                   footer_class: Formatters::Providers::CodexFooterFormatter).call
          else
            render_compact
          end
        end

        private

        # Renders the compact version of the Codex context file.
        #
        # @return [String] The generated content.
        def render_compact
          lines = []
          # Start with a Codex-specific header, then common overview
          lines.concat(render_header)
          lines << ''
          lines << 'Codex reads AGENTS.md before starting work in this repository.'
          lines << ''
          lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)

          # Use shared stack overview
          lines.concat(render_stack_overview)

          lines << '## Working agreements'
          lines << '- Prefer the MCP tools over guessing the Rails structure.'
          lines << '- Start with `detail:"summary"`, then drill into specifics.'
          lines << "- Run `#{ContextSummary.test_command(context)}` after behavior changes."
          lines << '- Run `bundle exec rubocop --parallel` before finishing substantial code changes.'
          lines << ''
          lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

          SharedAssistantGuidance.performance_security_and_rails_examples_lines.each { |l| lines << l }
          lines << ''

          append_compact_codex_models_section(lines, context[:models])

          # Use shared architecture rendering
          lines.concat(render_architecture)

          lines << '## MCP tool reference'
          lines << '- `rails_get_schema(detail:"summary")` to inspect tables first.'
          lines << '- `rails_get_model_details(model:"User")` for model-level detail.'
          lines << '- `rails_get_routes(detail:"summary")` before editing controllers or endpoints.'
          lines << '- `rails_get_controllers(controller:"UsersController")` for filters and params.'
          lines << '- `rails_get_config` and `rails_get_conventions` for stack decisions.'
          lines << '- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)` for targeted searches.'
          lines << ''
          lines << '## Codex notes'
          lines << '- This repository also includes `.mcp.json` for MCP client setup.'
          lines << '- See `.codex/README.md` for optional local Codex setup guidance.'
          lines << ''

          lines.join("\n")
        end

        # Appends a compact list of key models specific to Codex.
        #
        # @param lines [Array<String>] The array of lines to append to.
        # @param models [Hash] The models context.
        def append_compact_codex_models_section(lines, models)
          lines << '## Key models'
          unless models.is_a?(Hash) && !models[:error] && models.any?
            lines << '- Use `rails_get_model_details(detail:"summary")` to discover models.'
            lines << ''
            return
          end

          schema_tables = context.dig(:schema, :tables) || {}
          migrations    = context[:migrations]
          limit = @config.codex_compact_model_list_limit.to_i

          if limit <= 0
            lines << '- _Use `rails_get_model_details(detail:"summary")` for names — not listed here to save context._'
          else
            models.sort_by { |_n, d| -ContextSummary.model_complexity_score(d) }.first(limit).each do |name, data|
              assocs     = (data[:associations] || []).first(2).map { |a| "#{a[:type]} :#{a[:name]}" }.join(', ')
              table_name = data[:table_name]
              line = "- #{name}"
              line += " — #{assocs}" unless assocs.empty?

              cols = ContextSummary.top_columns(schema_tables[table_name])
              line += " [cols: #{cols.map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')}]" if cols.any?

              line += ' [recently migrated]' if table_name && ContextSummary.recently_migrated?(table_name, migrations)
              lines << line
            end
            remainder = models.size - limit
            lines << "- ...#{remainder} more — `rails_get_model_details(detail:\"summary\")`." if remainder.positive?
          end
          lines << ''
        end
      end
    end
  end
end
