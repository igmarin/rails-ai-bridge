# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates compact, imperative-tone rules for legacy `.cursorrules`.
      # In +:compact+ mode (default), output points editors at MCP tools and repo conventions.
      # In +:full+ mode, delegates to {MarkdownSerializer} with rules-style header and footer.
      class RulesSerializer < BaseProviderSerializer
        # @param context [Hash] The introspection context.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        def initialize(context, config: RailsAiBridge.configuration)
          super
        end

        # @return [String] Markdown for legacy `.cursorrules` (compact) or full Cursor-oriented document (full mode).
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
                                   header_class: Formatters::Providers::RulesHeaderFormatter,
                                   footer_class: Formatters::Providers::RulesFooterFormatter).call
          else
            render_compact
          end
        end

        private

        # Renders the compact version of the Cursor rules file.
        #
        # @return [String] The generated content.
        def render_compact
          lines = []
          # Custom header
          lines << "# #{context[:app_name]} — Project Rules"
          lines << ''
          lines << "Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}"
          lines << ''
          lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)

          # Use shared sections
          lines.concat(render_stack_overview)
          lines.concat(render_notable_gems)
          lines.concat(render_architecture)
          lines.concat(render_key_considerations)

          lines << ''
          lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

          lines << ''

          append_compact_cursorrules_models_section(lines, context[:models])

          # MCP tools
          lines << '## MCP Tool Reference'
          lines << ''
          lines << 'All introspection tools support detail:"summary"|"standard"|"full".'
          lines << 'Start with summary, drill into specifics with a filter.'
          lines << ''
          lines << '### rails_get_schema'
          lines << 'Params: table, detail, limit, offset, format'
          lines << '- `rails_get_schema(detail:"summary")` — all tables with column counts'
          lines << '- `rails_get_schema(table:"users")` — full detail for one table'
          lines << '- `rails_get_schema(detail:"summary", limit:20, offset:40)` — paginate'
          lines << ''
          lines << '### rails_get_model_details'
          lines << 'Params: model, detail'
          lines << '- `rails_get_model_details(detail:"summary")` — list model names'
          lines << '- `rails_get_model_details(model:"User")` — full associations, validations, scopes'
          lines << ''
          lines << '### rails_get_routes'
          lines << 'Params: controller, detail, limit, offset'
          lines << '- `rails_get_routes(detail:"summary")` — route counts per controller'
          lines << '- `rails_get_routes(controller:"users")` — routes for one controller'
          lines << ''
          lines << '### rails_get_controllers'
          lines << 'Params: controller, detail'
          lines << '- `rails_get_controllers(detail:"summary")` — names + action counts'
          lines << '- `rails_get_controllers(controller:"UsersController")` — full detail'
          lines << ''
          lines << '### Other tools'
          lines << '- `rails_get_config` — cache, session, middleware, timezone'
          lines << '- `rails_get_test_info` — framework, factories, CI'
          lines << '- `rails_get_gems` — categorized gem analysis'
          lines << '- `rails_get_conventions` — architecture patterns'
          lines << '- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)` — codebase search'
          lines << ''

          # Use shared footer
          lines.concat(render_footer)

          lines.join("\n")
        end

        # Appends a compact list of key models specific to Cursor rules.
        # @param lines [Array<String>] The array of lines to append to.
        # @param models [Hash] The models context.
        def append_compact_cursorrules_models_section(lines, models)
          return unless models.is_a?(Hash) && !models[:error] && models.any?

          limit = @config.copilot_compact_model_list_limit.to_i # uses copilot limit for now
          lines << "## Models (#{models.size} total)"
          if limit <= 0
            lines << '- _Use `rails_get_model_details(detail:"summary")` for names._'
          else
            models.keys.sort.first(limit).each do |name|
              data = models[name]
              assoc_count = (data[:associations] || []).size
              lines << "- #{name} (#{assoc_count} associations)"
            end
            remainder = models.size - limit
            lines << "- _...#{remainder} more — `rails_get_model_details(detail:\"summary\")`._" if remainder.positive?
          end
          lines << ''
        end
      end
    end
  end
end
