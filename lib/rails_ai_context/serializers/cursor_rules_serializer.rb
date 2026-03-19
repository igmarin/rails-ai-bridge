# frozen_string_literal: true

module RailsAiContext
  module Serializers
    # Generates .cursor/rules/*.mdc files in the new Cursor MDC format.
    # Each file is focused, <50 lines, with YAML frontmatter.
    # Also generates legacy .cursorrules for backward compatibility.
    class CursorRulesSerializer
      attr_reader :context

      def initialize(context)
        @context = context
      end

      # @param output_dir [String] Rails root path
      # @return [Hash] { written: [paths], skipped: [paths] }
      def call(output_dir)
        rules_dir = File.join(output_dir, ".cursor", "rules")
        FileUtils.mkdir_p(rules_dir)

        written = []
        skipped = []

        files = {
          "rails-engineering.mdc" => render_engineering_rule,
          "rails-project.mdc" => render_project_rule,
          "rails-models.mdc" => render_models_rule,
          "rails-controllers.mdc" => render_controllers_rule,
          "rails-mcp-tools.mdc" => render_mcp_tools_rule
        }

        files.each do |filename, content|
          next unless content
          filepath = File.join(rules_dir, filename)
          if File.exist?(filepath) && File.read(filepath) == content
            skipped << filepath
          else
            File.write(filepath, content)
            written << filepath
          end
        end

        { written: written, skipped: skipped }
      end

      private

      # Always-on engineering essentials (paired with rails-mcp-tools.mdc).
      def render_engineering_rule
        show_ov = SharedAssistantGuidance.overrides_file_exists_and_nonempty?
        body = SharedAssistantGuidance.cursor_engineering_mdc_body_lines(show_overrides_pointer: show_ov)
        (
          [
            "---",
            "description: \"Rails engineering rules — strong params, auth, performance, security\"",
            "alwaysApply: true",
            "---",
            ""
          ] + body
        ).join("\n")
      end

      # Always-on project overview rule (<50 lines)
      def render_project_rule
        lines = [
          "---",
          "description: \"Rails project context for #{context[:app_name]}\"",
          "alwaysApply: true",
          "---",
          "",
          "# #{context[:app_name]}",
          "",
          "Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}",
          ""
        ]

        schema = context[:schema]
        if schema && !schema[:error]
          lines << "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables"
        end

        models = context[:models]
        lines << "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]

        rline = ContextSummary.routes_stack_line(context)
        lines << rline if rline

        gems = context[:gems]
        if gems.is_a?(Hash) && !gems[:error]
          notable = gems[:notable_gems] || gems[:notable] || gems[:detected] || []
          grouped = notable.group_by { |g| g[:category]&.to_s || "other" }
          grouped.first(4).each do |cat, gem_list|
            lines << "- #{cat}: #{gem_list.map { |g| g[:name] }.first(6).join(', ')}#{', ...' if gem_list.size > 6}"
          end
        end

        conv = context[:conventions]
        if conv.is_a?(Hash) && !conv[:error]
          (conv[:architecture] || []).first(5).each { |p| lines << "- #{p}" }
        end

        lines << ""
        lines << "Engineering rules: rails-engineering.mdc. MCP tools: rails-mcp-tools.mdc."
        lines << "Always call with detail:\"summary\" first, then drill into specifics."

        lines.join("\n")
      end

      # Auto-attached when working in app/models/
      def render_models_rule
        models = context[:models]
        return nil unless models.is_a?(Hash) && !models[:error] && models.any?

        lines = [
          "---",
          "description: \"ActiveRecord models reference\"",
          "globs:",
          "  - \"app/models/**/*.rb\"",
          "alwaysApply: false",
          "---",
          "",
          "# Models (#{models.size})",
          ""
        ]

        models.keys.sort.first(30).each do |name|
          data = models[name]
          assocs = (data[:associations] || []).size
          lines << "- #{name} (#{assocs} associations, table: #{data[:table_name] || '?'})"
        end

        lines << "- ...#{models.size - 30} more" if models.size > 30
        lines << ""
        lines << "Use `rails_get_model_details` MCP tool with model:\"Name\" for full detail."

        lines.join("\n")
      end

      # Auto-attached when working in app/controllers/
      def render_controllers_rule
        data = context[:controllers]
        return nil unless data.is_a?(Hash) && !data[:error]
        controllers = data[:controllers] || {}
        return nil if controllers.empty?

        lines = [
          "---",
          "description: \"Controller reference\"",
          "globs:",
          "  - \"app/controllers/**/*.rb\"",
          "alwaysApply: false",
          "---",
          "",
          "# Controllers (#{controllers.size})",
          ""
        ]

        controllers.keys.sort.first(25).each do |name|
          info = controllers[name]
          action_count = info[:actions]&.size || 0
          lines << "- #{name} (#{action_count} actions)"
        end

        lines << "- ...#{controllers.size - 25} more" if controllers.size > 25
        lines << ""
        lines << "Use `rails_get_controllers` MCP tool with controller:\"Name\" for full detail."

        lines.join("\n")
      end

      # Always-on MCP tool reference
      def render_mcp_tools_rule # rubocop:disable Metrics/MethodLength
        lines = [
          "---",
          "description: \"MCP tool reference with parameters and examples\"",
          "alwaysApply: true",
          "---",
          "",
          "# MCP Tool Reference",
          "",
          "Detail levels: summary | standard (default) | full",
          "",
          "## rails_get_schema",
          "Params: table, detail, limit, offset, format",
          "- `rails_get_schema(detail:\"summary\")` — all tables with column counts",
          "- `rails_get_schema(table:\"users\")` — full detail for one table",
          "- `rails_get_schema(detail:\"summary\", limit:20, offset:40)` — paginate",
          "",
          "## rails_get_model_details",
          "Params: model, detail",
          "- `rails_get_model_details(detail:\"summary\")` — list model names",
          "- `rails_get_model_details(model:\"User\")` — full detail",
          "",
          "## rails_get_routes",
          "Params: controller, detail, limit, offset",
          "- `rails_get_routes(detail:\"summary\")` — counts per controller",
          "- `rails_get_routes(controller:\"users\")` — one controller",
          "",
          "## rails_get_controllers",
          "Params: controller, detail",
          "- `rails_get_controllers(detail:\"summary\")` — names + action counts",
          "- `rails_get_controllers(controller:\"UsersController\")` — full detail",
          "",
          "## Other tools",
          "- `rails_get_config` — cache, session, middleware",
          "- `rails_get_test_info` — framework, factories, CI",
          "- `rails_get_gems` — categorized gems",
          "- `rails_get_conventions` — architecture patterns",
          "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)`",
          "",
          "Start with detail:\"summary\", then drill into specifics."
        ]

        lines.join("\n")
      end
    end
  end
end
