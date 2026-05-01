# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates `.windsurfrules` within Windsurf's hard 6,000 character limit.
      # Always produces compact output regardless of +context_mode+.
      class WindsurfSerializer < BaseProviderSerializer
        # Maximum body length before truncation (buffer under Windsurf's 6K cap).
        MAX_CHARS = 5_800

        # @param context [Hash] Introspection hash from {Introspector#call}.
        # @param config [RailsAiBridge::Configuration] Bridge configuration.
        def initialize(context, config: RailsAiBridge.configuration)
          super
        end

        # @return [String] Windsurf rules file body, capped at +MAX_CHARS+ when over the limit.
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

        # Renders the compact version of the Windsurf rules file.
        # @return [String] The generated content.
        def render
          lines = []
          lines << "# #{context[:app_name]} — Rails #{context[:rails_version]}"
          lines << ''

          # Stack (very compact)
          lines.concat(render_stack_overview)

          # Gems (one line per category, aligning with base but keeping compact for space)
          gems = context[:gems]
          if gems.is_a?(Hash) && !gems[:error]
            notable = gems[:notable_gems] || gems[:notable] || gems[:detected] || []
            grouped = notable.group_by { |g| g[:category]&.to_s || 'other' }
            grouped.first(6).each do |cat, gem_list|
              lines << "#{cat}: #{gem_list.map { |g| g[:name] }.first(4).join(', ')}"
            end
          end

          lines << ''

          # Key models — complexity-sorted, with column hints and migration flags
          models = context[:models]
          if models.is_a?(Hash) && !models[:error] && models.any?
            schema_tables = context.dig(:schema, :tables) || {}
            migrations    = context[:migrations]

            lines << '## Key Models'
            sorted = models.sort_by { |_name, data| -ContextSummary.model_complexity_score(data) }
            sorted.first(20).each do |name, data|
              table_name = data[:table_name]
              line = "- #{name}"

              cols = ContextSummary.top_columns(schema_tables[table_name])
              line += " [cols: #{cols.map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')}]" if cols.any?

              line += ' [recently migrated]' if table_name && ContextSummary.recently_migrated?(table_name, migrations)

              lines << line
            end
            lines << "- ...#{models.size - 20} more" if models.size > 20
            lines << ''
          end

          # Architecture
          lines.concat(render_architecture)

          # Key Config Files (compacted version from BaseProviderSerializer)
          config_files = ContextSummary.safe_config_files(context.dig(:conventions, :config_files), limit: 3)
          if config_files.any?
            lines << '## Key Config Files'
            config_files.each { |f| lines << "- `#{f}`" }
            lines << ''
          end

          # Key Considerations (Performance & Security - compacted version)
          lines << '## Key Considerations'
          lines << '- Performance: N+1s, indexes. Use `rails_get_schema`.'
          lines << '- Security: Sanitize input, strong params.'
          lines << '- Data Drift: Use MCP tools for live data.'
          lines << ''

          # Commands (compacted version)
          lines << '## Commands'
          lines << '- `bin/dev` — dev server'
          lines << "- `#{ContextSummary.test_command(context)}` — run tests"
          lines << '- `bundle exec rubocop` — linter'
          lines << '- `rails db:migrate` — migrations'
          lines << ''

          # MCP tools — compact but complete (character budget is tight)
          lines << '## MCP Tools (detail:"summary"|"standard"|"full")'
          lines << '- rails_get_schema(table:"name"|detail:"sum"|limit:N)'
          lines << '- rails_get_model_details(model:"Name"|detail:"sum")'
          lines << '- rails_get_routes(controller:"name"|detail:"sum"|limit:N)'
          lines << '- rails_get_controllers(controller:"Name"|detail:"sum")'
          lines << '- rails_get_config — cache, session, middleware'
          lines << '- rails_get_test_info — framework, factories, CI'
          lines << '- rails_get_gems — categorized gems'
          lines << '- rails_get_conventions — architecture patterns'
          lines << '- `rails_search_code(pattern:"regex"|file_type:"rb"|max_results:N)`'
          lines << 'Start with detail:"summary", then drill into specifics.'
          lines << ''
          lines << '## Behavioral Rules'
          lines << '- Adhere to Conventions'
          lines << '- Schema as Source of Truth'
          lines << '- Respect Existing Logic'
          lines << '- Write Tests'
          lines << '- Verify Correctness with `rubocop` and tests'

          lines.join("\n")
        end
      end
    end
  end
end
