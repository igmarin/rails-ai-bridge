# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Generates GitHub Copilot instructions.
    # In :compact mode (default), produces ≤500 lines with MCP tool references.
    # In :full mode, delegates to MarkdownSerializer with Copilot header.
    class CopilotSerializer
      attr_reader :context

      def initialize(context, config: RailsAiBridge.configuration)
        @context = context
        @config = config
      end

      def call
        if @config.context_mode == :full
          MarkdownSerializer.new(context,
            header_class: Formatters::CopilotHeaderFormatter,
            footer_class: Formatters::CopilotFooterFormatter
          ).call
        else
          render_compact
        end
      end

      private

      def render_compact
        lines = []
        lines << "# #{context[:app_name]} — Copilot Context"
        lines << ""
        lines << "Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}"
        lines << ""
        lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)
        # Stack overview
        lines << "## Stack"
        schema = context[:schema]
        lines << "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables" if schema && !schema[:error]

        models = context[:models]
        lines << "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]

        line = ContextSummary.routes_stack_line(context)
        lines << line if line

        # Gems by category
        gems = context[:gems]
        if gems.is_a?(Hash) && !gems[:error]
          notable = gems[:notable_gems] || gems[:notable] || gems[:detected] || []
          notable.group_by { |g| g[:category]&.to_s || "other" }.each do |cat, list|
            lines << "- #{cat}: #{list.map { |g| g[:name] }.join(', ')}"
          end
        end

        lines << ""
        lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

        SharedAssistantGuidance.performance_security_and_rails_examples_lines.each { |l| lines << l }
        lines << ""

        # Architecture
        conv = context[:conventions]
        if conv.is_a?(Hash) && !conv[:error]
          arch = conv[:architecture] || []
          patterns = conv[:patterns] || []
          if arch.any? || patterns.any?
            lines << "## Architecture"
            arch.each { |p| lines << "- #{p}" }
            patterns.first(10).each { |p| lines << "- #{p}" }
            lines << ""
          end
        end

        append_compact_copilot_models_section(lines, models)


        # MCP tools
        lines << "## MCP Tool Reference"
        lines << ""
        lines << "This project has MCP tools for live introspection."
        lines << "**Always start with `detail:\"summary\"`, then drill into specifics.**"
        lines << ""
        lines << "### Detail levels (schema, routes, models, controllers)"
        lines << "- `summary` — names + counts (default limit: 50)"
        lines << "- `standard` — names + key details (default limit: 15, this is the default)"
        lines << "- `full` — everything including indexes, FKs (default limit: 5)"
        lines << ""
        lines << "### rails_get_schema"
        lines << "Params: `table`, `detail`, `limit`, `offset`, `format`"
        lines << "- `rails_get_schema(detail:\"summary\")` — all tables with column counts"
        lines << "- `rails_get_schema(table:\"users\")` — full detail for one table"
        lines << "- `rails_get_schema(detail:\"summary\", limit:20, offset:40)` — paginate"
        lines << ""
        lines << "### rails_get_model_details"
        lines << "Params: `model`, `detail`"
        lines << "- `rails_get_model_details(detail:\"summary\")` — list all model names"
        lines << "- `rails_get_model_details(model:\"User\")` — associations, validations, scopes, enums"
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

        # Conventions
        lines << "## Conventions"
        lines << "- Follow existing patterns and naming conventions"
        lines << "- Use MCP tools to check schema before writing migrations"
        lines << "- Run `#{ContextSummary.test_command(context)}` after changes"
        lines << ""

        lines.join("\n")
      end

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
