# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates .github/instructions/*.instructions.md files with applyTo frontmatter
      # for GitHub Copilot path-specific instructions.
      class CopilotInstructionsSerializer
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def call(output_dir)
        dir = File.join(output_dir, ".github", "instructions")
        FileUtils.mkdir_p(dir)

        written = []
        skipped = []

        files = {
          "rails-models.instructions.md" => render_models_instructions,
          "rails-controllers.instructions.md" => render_controllers_instructions,
          "rails-mcp-tools.instructions.md" => render_mcp_tools_instructions
        }

        files.each do |filename, content|
          next unless content
          filepath = File.join(dir, filename)
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

      def render_models_instructions
        models = context[:models]
        return nil unless models.is_a?(Hash) && !models[:error] && models.any?

        lines = [
          "---",
          "applyTo: \"app/models/**/*.rb\"",
          "---",
          "",
          "# ActiveRecord Models (#{models.size})",
          "",
          "Use `rails_get_model_details` MCP tool for full details.",
          ""
        ]

        models.keys.sort.first(30).each do |name|
          data = models[name]
          assocs = (data[:associations] || []).size
          lines << "- #{name} (#{assocs} associations)"
        end

        lines << "- ...#{models.size - 30} more" if models.size > 30
        lines.join("\n")
      end

      def render_controllers_instructions
        data = context[:controllers]
        return nil unless data.is_a?(Hash) && !data[:error]
        controllers = data[:controllers] || {}
        return nil if controllers.empty?

        lines = [
          "---",
          "applyTo: \"app/controllers/**/*.rb\"",
          "---",
          "",
          "# Controllers (#{controllers.size})",
          "",
          "Use `rails_get_controllers` MCP tool for full details.",
          ""
        ]

        controllers.keys.sort.first(25).each do |name|
          info = controllers[name]
          actions = info[:actions]&.size || 0
          lines << "- #{name} (#{actions} actions)"
        end

        lines.join("\n")
      end

      def render_mcp_tools_instructions # rubocop:disable Metrics/MethodLength
        lines = [
          "---",
          "applyTo: \"**/*\"",
          "---",
          "",
          "# MCP Tool Reference",
          "",
          "This project has MCP tools for live introspection.",
          "**Start with `detail:\"summary\"`, then drill into specifics.**",
          "",
          "## Detail levels (schema, routes, models, controllers)",
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
          "- `rails_get_model_details(model:\"User\")` — full associations, validations, scopes",
          "",
          "## rails_get_routes",
          "Params: `controller`, `detail`, `limit`, `offset`",
          "- `rails_get_routes(detail:\"summary\")` — route counts per controller",
          "- `rails_get_routes(controller:\"users\")` — routes for one controller",
          "",
          "## rails_get_controllers",
          "Params: `controller`, `detail`",
          "- `rails_get_controllers(detail:\"summary\")` — names + action counts",
          "- `rails_get_controllers(controller:\"UsersController\")` — actions, filters, params",
          "",
          "## Other tools",
          "- `rails_get_config` — cache store, session, timezone, middleware",
          "- `rails_get_test_info` — test framework, factories/fixtures, CI config",
          "- `rails_get_gems` — notable gems categorized by function",
          "- `rails_get_conventions` — architecture patterns, directory structure",
          "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)` — codebase search"
        ]

        lines.join("\n")
      end
      end
    end
  end
end
