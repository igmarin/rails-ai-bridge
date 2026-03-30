# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Generates .windsurfrules within Windsurf's hard 6,000 character limit.
    # Always produces compact output regardless of context_mode.
    class WindsurfSerializer
      MAX_CHARS = 5_800 # Leave buffer below 6K limit

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def call
        content = render
        # HARD enforce character limit — Windsurf silently truncates
        if content.length > MAX_CHARS
          content = content[0...MAX_CHARS]
          content += "\n\n# Use MCP tools for full details."
        end
        content
      end

      private

      def render
        lines = []
        lines << "# #{context[:app_name]} — Rails #{context[:rails_version]}"
        lines << ""

        # Stack (very compact)
        schema = context[:schema]
        lines << "Database: #{schema[:adapter]}, #{schema[:total_tables]} tables" if schema && !schema[:error]

        models = context[:models]
        lines << "Models: #{models.size}" if models.is_a?(Hash) && !models[:error]

        routes = context[:routes]
        lines << "Routes: #{routes[:total_routes]}" if routes && !routes[:error]

        # Gems (one line per category)
        gems = context[:gems]
        if gems.is_a?(Hash) && !gems[:error]
          notable = gems[:notable_gems] || gems[:notable] || gems[:detected] || []
          grouped = notable.group_by { |g| g[:category]&.to_s || "other" }
          grouped.first(6).each do |cat, gem_list|
            lines << "#{cat}: #{gem_list.map { |g| g[:name] }.first(4).join(', ')}"
          end
        end

        lines << ""

        # Key models — complexity-sorted, with column hints and migration flags
        if models.is_a?(Hash) && !models[:error] && models.any?
          schema_tables = context.dig(:schema, :tables) || {}
          migrations    = context[:migrations]

          lines << "# Key models"
          sorted = models.sort_by { |_name, data| -ContextSummary.model_complexity_score(data) }
          sorted.first(20).each do |name, data|
            table_name = data[:table_name]
            line = "- #{name}"

            cols = ContextSummary.top_columns(schema_tables[table_name])
            line += " [cols: #{cols.map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')}]" if cols.any?

            line += " [recently migrated]" if table_name && ContextSummary.recently_migrated?(table_name, migrations)

            lines << line
          end
          lines << "- ...#{models.size - 20} more" if models.size > 20
          lines << ""
        end

        # Architecture
        conv = context[:conventions]
        if conv.is_a?(Hash) && !conv[:error]
          arch = conv[:architecture] || []
          if arch.any?
            lines << "# Architecture"
            arch.first(5).each { |p| lines << "- #{p}" }
            lines << ""
          end
        end

        # MCP tools — compact but complete (character budget is tight)
        lines << "# MCP Tools (detail:\"summary\"|\"standard\"|\"full\")"
        lines << "- rails_get_schema(table:\"name\"|detail:\"summary\"|limit:N|offset:N)"
        lines << "- rails_get_model_details(model:\"Name\"|detail:\"summary\")"
        lines << "- rails_get_routes(controller:\"name\"|detail:\"summary\"|limit:N|offset:N)"
        lines << "- rails_get_controllers(controller:\"Name\"|detail:\"summary\")"
        lines << "- rails_get_config — cache, session, middleware"
        lines << "- rails_get_test_info — framework, factories, CI"
        lines << "- rails_get_gems — categorized gems"
        lines << "- rails_get_conventions — architecture patterns"
        lines << "- rails_search_code(pattern:\"regex\"|file_type:\"rb\"|max_results:N)"
        lines << "Start with detail:\"summary\", then drill into specifics."
        lines << ""
        lines << "# Rules"
        lines << "- Follow existing patterns"
        lines << "- Check schema via MCP before writing migrations"
        lines << "- Run `#{ContextSummary.test_command(context)}` after changes"

        lines.join("\n")
      end
    end
  end
end
