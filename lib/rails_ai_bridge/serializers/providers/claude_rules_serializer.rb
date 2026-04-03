# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates `.claude/rules/` markdown files for Claude Code auto-discovery.
      # Quick-reference lists keep {ClaudeSerializer} output smaller.
      class ClaudeRulesSerializer
        # @return [Hash] Introspection context passed to serializers.
        attr_reader :context

        # @param context [Hash] Introspection hash from {Introspector#call}.
        def initialize(context)
          @context = context
        end

        # Writes schema, models, and MCP reference files when content changes.
        #
        # @param output_dir [String] Root directory where `.claude/rules` is created.
        # @return [Hash<Symbol, Array<String>>] +:written+ and +:skipped+ arrays of absolute file paths.
        def call(output_dir)
          rules_dir = File.join(output_dir, ".claude", "rules")
          FileUtils.mkdir_p(rules_dir)

          written = []
          skipped = []

          files = {
            "rails-schema.md" => render_schema_reference,
            "rails-models.md" => render_models_reference,
            "rails-mcp-tools.md" => render_mcp_tools_reference
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

        # @return [String, nil] Table listing markdown, or +nil+ when schema is missing or empty.
        def render_schema_reference
          schema = context[:schema]
          return nil unless schema.is_a?(Hash) && !schema[:error]
          tables = schema[:tables] || {}
          return nil if tables.empty?

          lines = [
            "# Database Tables (#{tables.size})",
            "",
            "For full column details, use the `rails_get_schema` MCP tool.",
            "Call with `detail:\"summary\"` first, then `table:\"name\"` for specifics.",
            ""
          ]

          tables.keys.sort.each do |name|
            data = tables[name]
            col_count = data[:columns]&.size || 0
            pk = data[:primary_key] || "id"
            lines << "- #{name} (#{col_count} cols, pk: #{pk})"
          end

          lines.join("\n")
        end

        # @return [String, nil] Model listing markdown, or +nil+ when models are missing or empty.
        def render_models_reference
          models = context[:models]
          return nil unless models.is_a?(Hash) && !models[:error]
          return nil if models.empty?

          lines = [
            "# ActiveRecord Models (#{models.size})",
            "",
            "For full details, use `rails_get_model_details` MCP tool.",
            "Call with no args to list all, then `model:\"Name\"` for specifics.",
            ""
          ]

          models.keys.sort.each do |name|
            data = models[name]
            assocs = (data[:associations] || []).size
            vals = (data[:validations] || []).size
            table = data[:table_name]
            line = "- #{name}"
            line += " (table: #{table})" if table
            line += " — #{assocs} assocs, #{vals} validations"
            lines << line
          end

          lines.join("\n")
        end

        # @return [String] MCP tool reference markdown for Claude rules.
        def render_mcp_tools_reference # rubocop:disable Metrics/MethodLength
          lines = [
            "# MCP Tool Reference",
            "",
            "All introspection tools support a `detail` parameter:",
            "- `summary` — names + counts (default limit: 50)",
            "- `standard` — names + key details (default limit: 15, this is the default)",
            "- `full` — everything including indexes, FKs (default limit: 5)",
            "",
            "## rails_get_schema",
            "Params: `table`, `detail`, `limit`, `offset`, `format`",
            "- `rails_get_schema(detail:\"summary\")` — all tables with column counts",
            "- `rails_get_schema(table:\"users\")` — full detail for one table",
            "- `rails_get_schema(detail:\"summary\", limit:20, offset:40)` — paginate",
            "",
            "## rails_get_model_details",
            "Params: `model`, `detail`",
            "- `rails_get_model_details(detail:\"summary\")` — list all model names",
            "- `rails_get_model_details(model:\"User\")` — associations, validations, scopes, enums, callbacks",
            "- `rails_get_model_details(detail:\"full\")` — all models with full association lists",
            "",
            "## rails_get_routes",
            "Params: `controller`, `detail`, `limit`, `offset`",
            "- `rails_get_routes(detail:\"summary\")` — route counts per controller",
            "- `rails_get_routes(controller:\"users\")` — routes for one controller",
            "- `rails_get_routes(detail:\"full\", limit:50)` — full table with route names",
            "",
            "## rails_get_controllers",
            "Params: `controller`, `detail`",
            "- `rails_get_controllers(detail:\"summary\")` — names + action counts",
            "- `rails_get_controllers(controller:\"UsersController\")` — actions, filters, strong params",
            "",
            "## Other tools (no detail param)",
            "- `rails_get_config` — cache store, session, timezone, middleware, initializers",
            "- `rails_get_test_info` — test framework, factories/fixtures, CI config, coverage",
            "- `rails_get_gems` — notable gems categorized by function",
            "- `rails_get_conventions` — architecture patterns, directory structure",
            "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)` — codebase search",
            "",
            "## Workflow",
            "1. Start with `detail:\"summary\"` to understand the landscape",
            "2. Drill into specifics with filters (`table:`, `model:`, `controller:`)",
            "3. Use `detail:\"full\"` only when you need indexes, FKs, constraints",
            "4. Paginate large results with `limit` and `offset`"
          ]

          lines.join("\n")
        end
      end
    end
  end
end
