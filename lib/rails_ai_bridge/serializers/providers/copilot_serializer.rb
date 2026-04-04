# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates GitHub Copilot instruction markdown (`.github/copilot-instructions.md` or compact variant).
      # In +:compact+ mode (default), output includes MCP tool reference and Copilot-specific header.
      # In +:full+ mode, delegates to {MarkdownSerializer} with Copilot header and footer formatters.
      class CopilotSerializer < BaseProviderSerializer
        # @param context [Hash] The introspection context.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        def initialize(context, config: RailsAiBridge.configuration)
          super(context, config: config)
        end

        # @return [String] Markdown for `.github/copilot-instructions.md` (full mode) or compact Copilot context (compact mode).
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
              header_class: Formatters::Providers::CopilotHeaderFormatter,
              footer_class: Formatters::Providers::CopilotFooterFormatter
            ).call
          else
            render_compact
          end
        end

        private

        # @return [Array<String>] Header lines with a Copilot-specific title.
        def render_header
          super.tap { |lines| lines[0] = "# #{context[:app_name]} — Copilot Context" }
        end

        # @return [String] Compact Copilot instructions with stack, models, and MCP reference.
        def render_compact
          lines = []
          lines.concat(render_header)
          lines << ""
          lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)

          lines.concat(render_stack_overview)

          lines.concat(render_notable_gems)

          lines << ""
          lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

          SharedAssistantGuidance.performance_security_and_rails_examples_lines.each { |l| lines << l }
          lines << ""

          lines.concat(render_architecture)

          append_compact_copilot_models_section(lines, context[:models])

          lines.concat(render_mcp_tool_reference)

          lines.concat(render_footer)

          lines.join("\n")
        end

        # Renders Copilot-specific MCP tool reference.
        # @return [Array<String>] Lines for the MCP tool reference.
        def render_mcp_tool_reference
          lines = [
            "## MCP Tool Reference",
            "",
            "This project has MCP tools for live introspection.",
            "**Always start with `detail:\"summary\"`, then drill into specifics.**",
            "",
            "### Detail levels (schema, routes, models, controllers)",
            "- `summary` — names + counts (default limit: 50)",
            "- `standard` — names + key details (default limit: 15, this is the default)",
            "- `full` — everything including indexes, FKs (default limit: 5)",
            "",
            "### rails_get_schema",
            "Params: `table`, `detail`, `limit`, `offset`, `format`",
            "- `rails_get_schema(detail:\"summary\")` — all tables with column counts",
            "- `rails_get_schema(table:\"users\")` — full detail for one table",
            "- `rails_get_schema(detail:\"summary\", limit:20, offset:40)` — paginate",
            "",
            "### rails_get_model_details",
            "Params: `model`, `detail`",
            "- `rails_get_model_details(detail:\"summary\")` — list all model names",
            "- `rails_get_model_details(model:\"User\")` — associations, validations, scopes, enums"
          ]
          lines << ""
          lines << "### rails_get_routes"
          lines << "Params: `controller`, `detail`, `limit`, `offset`"
          lines << "- `rails_get_routes(detail:\"summary\")` — route counts per controller"
          lines << "- `rails_get_routes(controller:\"users\")` — routes for one controller"
          lines << ""
          lines << "### rails_get_controllers"
          lines << "Params: `controller`, `detail`"
          lines << "- `rails_get_controllers(detail:\"summary\")` — names + action counts"
          lines << "- `rails_get_controllers(controller:\"UsersController\")` — actions, filters, params"
          lines << ""
          lines << "### Other tools"
          lines << "- `rails_get_config` — cache store, session, timezone, middleware"
          lines << "- `rails_get_test_info` — test framework, factories/fixtures, CI config"
          lines << "- `rails_get_gems` — notable gems categorized by function"
          lines << "- `rails_get_conventions` — architecture patterns, directory structure"
          lines << "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)` — codebase search"
          lines << ""
          lines << "_The same MCP reference also appears under `.github/instructions/rails-mcp-tools.instructions.md` and `.cursor/rules/rails-mcp-tools.mdc` for path-scoped clients._"
          lines << ""
          lines
        end

        # Appends a compact list of key models specific to Copilot.
        # @param lines [Array<String>] The array of lines to append to.
        # @param models [Hash] The models context.
        def append_compact_copilot_models_section(lines, models)
          return unless models.is_a?(Hash) && !models[:error] && models.any?

          schema_tables = context.dig(:schema, :tables) || {}
          migrations    = context[:migrations]
          limit = @config.copilot_compact_model_list_limit.to_i

          lines << "## Models (#{models.size} total)"
          if limit <= 0
            lines << "- _No model names listed here — use `rails_get_model_details(detail:\"summary\")` for the full list._"
          else
            models.sort_by { |_n, d| -ContextSummary.model_complexity_score(d) }.first(limit).each do |name, data|
              assocs     = (data[:associations] || []).first(3).map { |a| "#{a[:type]} :#{a[:name]}" }.join(", ")
              table_name = data[:table_name]
              line = "- **#{name}**"
              line += " — #{assocs}" unless assocs.empty?

              cols = ContextSummary.top_columns(schema_tables[table_name])
              line += " [cols: #{cols.map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')}]" if cols.any?

              line += " [recently migrated]" if table_name && ContextSummary.recently_migrated?(table_name, migrations)
              lines << line
            end
            remainder = models.size - limit
            lines << "- _...#{remainder} more — use `rails_get_model_details(detail:\"summary\")`._" if remainder.positive?
          end
          lines << ""
        end
      end
    end
  end
end
