# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates `.devin/rules/*.md` files for Devin rule discovery.
      # Each file is hard-capped at {MAX_CHARS_PER_FILE} characters (under Devin's 6K limit).
      class DevinRulesSerializer
        # Per-file character cap before truncation.
        MAX_CHARS_PER_FILE = 5_800

        # @return [Hash] Introspection context passed to serializers.
        attr_reader :context

        # @param context [Hash] Introspection hash from {Introspector#call}.
        def initialize(context)
          @context = context
        end

        # Writes rule markdown files under `.devin/rules/` when content changes.
        #
        # @param output_dir [String] Root directory (typically the Rails app root) where `.devin/rules` is created.
        # @return [Hash<Symbol, Array<String>>] +:written+ and +:skipped+ arrays of absolute file paths.
        def call(output_dir)
          rules_dir = File.join(output_dir, '.devin', 'rules')
          FileUtils.mkdir_p(rules_dir)

          written = []
          skipped = []

          files = {
            'rails-context.md' => render_context_rule,
            'rails-mcp-tools.md' => render_mcp_tools_rule
          }

          files.each do |filename, content|
            next unless content

            # Enforce Devin's 6K limit
            content = content[0...MAX_CHARS_PER_FILE] if content.length > MAX_CHARS_PER_FILE

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

        # @return [String] Context overview from {DevinSerializer}.
        def render_context_rule
          DevinSerializer.new(context).call
        end

        # @return [String] Standalone MCP tool cheat sheet for Devin.
        def render_mcp_tools_rule
          lines = [
            '# MCP Tool Reference',
            '',
            'Detail levels: summary | standard (default) | full',
            '',
            '## Schema',
            'rails_get_schema(table:"name"|detail:"summary"|limit:N|offset:N)',
            '',
            '## Models',
            'rails_get_model_details(model:"Name"|detail:"summary")',
            '',
            '## Routes',
            'rails_get_routes(controller:"name"|detail:"summary"|limit:N|offset:N)',
            '',
            '## Controllers',
            'rails_get_controllers(controller:"Name"|detail:"summary")',
            '',
            '## Other',
            '- rails_get_config — cache, session, middleware',
            '- rails_get_test_info — framework, factories, CI',
            '- rails_get_gems — categorized gems',
            '- rails_get_conventions — architecture patterns',
            '- rails_search_code(pattern:"regex"|file_type:"rb"|max_results:N)',
            '',
            'Start with detail:"summary", then drill into specifics.'
          ]

          lines.join("\n")
        end
      end
    end
  end
end
