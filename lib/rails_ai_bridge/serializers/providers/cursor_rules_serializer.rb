# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates `.cursor/rules/*.mdc` files in the Cursor MDC format (YAML frontmatter, focused bodies).
      # Complements legacy `.cursorrules` from {RulesSerializer}.
      class CursorRulesSerializer
        # @return [Hash] Introspection context passed to serializers.
        attr_reader :context

        # @param context [Hash] Introspection hash from {Introspector#call}.
        def initialize(context)
          @context = context
        end

        # Writes MDC rule files under `.cursor/rules/` when content changes.
        #
        # @param output_dir [String] Root directory where `.cursor/rules` is created.
        # @return [Hash<Symbol, Array<String>>] +:written+ and +:skipped+ arrays of absolute file paths.
        def call(output_dir)
          rules_dir = File.join(output_dir, '.cursor', 'rules')
          FileUtils.mkdir_p(rules_dir)

          written = []
          skipped = []

          files = {
            'rails-engineering.mdc' => render_engineering_rule,
            'rails-project.mdc' => render_project_rule,
            'rails-models.mdc' => render_models_rule,
            'rails-controllers.mdc' => render_controllers_rule,
            'rails-mcp-tools.mdc' => render_mcp_tools_rule
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

        # @return [String] Always-on engineering MDC body (paired with `rails-mcp-tools.mdc`).
        def render_engineering_rule
          show_ov = SharedAssistantGuidance.overrides_file_exists_and_nonempty?
          body = SharedAssistantGuidance.cursor_engineering_mdc_body_lines(show_overrides_pointer: show_ov)
          lines = [
            '---',
            'description: "Rails engineering rules — strong params, auth, performance, security"',
            'alwaysApply: true',
            '---',
            ''
          ] + body
          lines << "- Run `#{ContextSummary.test_command(context)}` after changes"
          lines.join("\n")
        end

        # @return [String] Always-on project overview MDC (stack, gems, architecture hints).
        def render_project_rule
          ProjectRuleBuilder.new(context).render
        end

        # Builds Cursor's always-on project overview rule.
        class ProjectRuleBuilder
          def initialize(context)
            @context = context
            @sections = context.slice(:schema, :models, :gems, :conventions)
          end

          # @return [String] Cursor MDC project overview rule
          def render
            (header_lines + stack_lines + footer_lines).join("\n")
          end

          private

          def header_lines
            app_name = @context[:app_name]
            [
              '---',
              "description: \"Rails project context for #{app_name}\"",
              'alwaysApply: true',
              '---',
              '',
              "# #{app_name}",
              '',
              "Rails #{@context[:rails_version]} | Ruby #{@context[:ruby_version]}",
              ''
            ]
          end

          def stack_lines
            [database_line, models_line, ContextSummary.routes_stack_line(@context), endpoint_focus_lines,
             notable_gem_lines, architecture_lines].flatten.compact
          end

          def database_line
            return unless schema && !schema[:error]

            table_count = schema[:total_tables] || schema[:tables]&.size
            "- Database: #{schema[:adapter]} — #{table_count} tables"
          end

          def models_line
            "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]
          end

          def endpoint_focus_lines
            EndpointFocusLines.new(@context).to_a
          end

          def notable_gem_lines
            return [] unless gems.is_a?(Hash) && !gems[:error]

            notable_gems.group_by { |gem| gem[:category]&.to_s || 'other' }
                        .first(4)
                        .map { |category, gem_list| NotableGemLine.new(category, gem_list).to_s }
          end

          def notable_gems
            gems[:notable_gems] || gems[:notable] || gems[:detected] || []
          end

          def architecture_lines
            return [] unless conventions.is_a?(Hash) && !conventions[:error]

            (conventions[:architecture] || []).first(5).map { |pattern| "- #{pattern}" }
          end

          def footer_lines
            [
              '',
              'Engineering rules: rails-engineering.mdc. MCP tools: rails-mcp-tools.mdc.',
              'Always call with detail:"summary" first, then drill into specifics.'
            ]
          end

          def schema = @sections[:schema]

          def models = @sections[:models]

          def gems = @sections[:gems]

          def conventions = @sections[:conventions]

          # Formats route focus lines for the project rule.
          class EndpointFocusLines
            def initialize(context)
              @focus_lines = ContextSummary.route_focus_lines(context, limit: 3)
            end

            # @return [Array<String>] formatted endpoint-focus lines
            def to_a
              return [] if @focus_lines.empty?

              ['- Endpoint focus:'] + @focus_lines.map { |line| "  #{line.delete_prefix('- ')}" }
            end
          end

          # Formats one notable-gem category line for the project rule.
          class NotableGemLine
            def initialize(category, gem_list)
              @category = category
              @gem_list = gem_list
            end

            # @return [String] formatted notable-gem category line
            def to_s
              "- #{@category}: #{gem_names.first(6).join(', ')}#{overflow_suffix}"
            end

            private

            def gem_names
              @gem_list.pluck(:name)
            end

            def overflow_suffix
              ', ...' if @gem_list.size > 6
            end
          end
        end
        private_constant :ProjectRuleBuilder

        # @return [String, nil] Models MDC for `app/models/**`, or +nil+ if no models.
        def render_models_rule
          models = context[:models]
          return nil unless models.is_a?(Hash) && !models[:error] && models.any?

          lines = [
            '---',
            'description: "ActiveRecord models reference"',
            'globs:',
            '  - "app/models/**/*.rb"',
            'alwaysApply: false',
            '---',
            '',
            "# Models (#{models.size})",
            ''
          ]

          schema_tables = context.dig(:schema, :tables) || {}
          migrations    = context[:migrations]

          sorted = ContextSummary.models_by_relevance(models, context: context)
          sorted.first(30).each do |name, data|
            assocs     = (data[:associations] || []).size
            table_name = data[:table_name]
            enum_names = (data[:enums] || {}).keys

            line = "- #{name} (#{assocs} associations, table: #{table_name || '?'})"
            line += " [enums: #{enum_names.join(', ')}]" if enum_names.any?

            cols = ContextSummary.top_columns(schema_tables[table_name])
            line += " [cols: #{cols.map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')}]" if cols.any?

            line += ' [recently migrated]' if table_name && ContextSummary.recently_migrated?(table_name, migrations)

            lines << line
          end

          lines << "- ...#{models.size - 30} more" if models.size > 30
          lines << ''
          lines << 'Use `rails_get_model_details` MCP tool with model:"Name" for full detail.'

          lines.join("\n")
        end

        # @return [String, nil] Controllers MDC for `app/controllers/**/*.rb`, or +nil+ if none.
        def render_controllers_rule
          data = context[:controllers]
          return nil unless data.is_a?(Hash) && !data[:error]

          controllers = data[:controllers] || {}
          return nil if controllers.empty?

          routes_by_ctrl = context.dig(:routes, :by_controller) || {}

          lines = [
            '---',
            'description: "Controller reference"',
            'globs:',
            '  - "app/controllers/**/*.rb"',
            'alwaysApply: false',
            '---',
            '',
            "# Controllers (#{controllers.size})",
            ''
          ]

          controllers.keys.sort_by { |name| controller_sort_key(name, routes_by_ctrl) }.first(25).each do |name|
            info = controllers[name]
            # Derive route key: "UsersController" → "users", "Admin::UsersController" → "admin/users"
            route_key = name.gsub(/Controller\z/, '').underscore
            routes = routes_by_ctrl[route_key] || []

            if routes.any?
              action_lines = routes.first(6).map { |r| "#{r[:verb]} #{r[:action]}" }.join(', ')
              lines << "- #{name}: #{action_lines}"
            else
              action_count = info[:actions]&.size || 0
              lines << "- #{name} (#{action_count} actions)"
            end
          end

          lines << "- ...#{controllers.size - 25} more" if controllers.size > 25
          lines << ''
          lines << 'Use `rails_get_controllers` MCP tool with controller:"Name" for full detail.'

          lines.join("\n")
        end

        def controller_sort_key(name, routes_by_ctrl)
          clean_name = name.gsub(/Controller\z/, '').underscore
          [-Array(routes_by_ctrl[clean_name]).size, name]
        end

        # @return [String] Always-on MCP tool reference MDC.
        def render_mcp_tools_rule
          lines = [
            '---',
            'description: "MCP tool reference with parameters and examples"',
            'alwaysApply: true',
            '---',
            '',
            '# MCP Tool Reference',
            '',
            'Detail levels: summary | standard (default) | full',
            '',
            '## rails_get_schema',
            'Params: table, detail, limit, offset, format',
            '- `rails_get_schema(detail:"summary")` — all tables with column counts',
            '- `rails_get_schema(table:"users")` — full detail for one table',
            '- `rails_get_schema(detail:"summary", limit:20, offset:40)` — paginate',
            '',
            '## rails_get_model_details',
            'Params: model, detail',
            '- `rails_get_model_details(detail:"summary")` — list model names',
            '- `rails_get_model_details(model:"User")` — full detail',
            '',
            '## rails_get_routes',
            'Params: controller, detail, limit, offset',
            '- `rails_get_routes(detail:"summary")` — counts per controller',
            '- `rails_get_routes(controller:"users")` — one controller',
            '',
            '## rails_get_controllers',
            'Params: controller, detail',
            '- `rails_get_controllers(detail:"summary")` — names + action counts',
            '- `rails_get_controllers(controller:"UsersController")` — full detail',
            '',
            '## Other tools',
            '- `rails_get_config` — cache, session, middleware',
            '- `rails_get_test_info` — framework, factories, CI',
            '- `rails_get_gems` — categorized gems',
            '- `rails_get_conventions` — architecture patterns',
            '- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)`',
            '',
            'Start with detail:"summary", then drill into specifics.'
          ]

          lines.join("\n")
        end
      end
    end
  end
end
