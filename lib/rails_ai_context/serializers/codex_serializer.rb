# frozen_string_literal: true

module RailsAiContext
  module Serializers
    # Generates OpenAI Codex project guidance as Markdown suitable for +AGENTS.md+.
    #
    # In +:compact+ mode (default), output is bounded and MCP-focused. In +:full+ mode,
    # delegates to {FullCodexSerializer}, which extends {MarkdownSerializer} with Codex-oriented framing.
    #
    # @since 0.8.0
    class CodexSerializer
      attr_reader :context

      # @param context [Hash] Introspection hash from {Introspector#call} (e.g. +:app_name+, +:schema+, +:models+).
      def initialize(context)
        @context = context
      end

      # @return [String] Markdown written to +AGENTS.md+ by {ContextFileSerializer}.
      def call
        if RailsAiContext.configuration.context_mode == :full
          FullCodexSerializer.new(context).call
        else
          render_compact
        end
      end

      private

      def render_compact
        lines = []
        lines << "# AGENTS.md"
        lines << ""
        lines << "Codex reads this file before starting work in this repository."
        lines << ""
        lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)

        lines << "## Project overview"
        lines << "- App: #{context[:app_name]}"
        lines << "- Stack: Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}"

        schema = context[:schema]
        if schema && !schema[:error]
          lines << "- Database: #{schema[:adapter]} (#{schema[:total_tables]} tables)"
        end

        models = context[:models]
        if models.is_a?(Hash) && !models[:error]
          lines << "- Models: #{models.size}"
        end

        line = ContextSummary.routes_stack_line(context)
        lines << line if line

        lines << ""
        lines << "## Working agreements"
        lines << "- Prefer the MCP tools over guessing the Rails structure."
        lines << "- Start with `detail:\"summary\"`, then drill into specifics."
        lines << "- Run `bundle exec rspec` after behavior changes."
        lines << "- Run `bundle exec rubocop --parallel` before finishing substantial code changes."
        lines << ""
        lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

        SharedAssistantGuidance.performance_security_and_rails_examples_lines.each { |l| lines << l }
        lines << ""

        append_compact_codex_models_section(lines, models)

        conv = context[:conventions]
        if conv.is_a?(Hash) && !conv[:error]
          architecture = conv[:architecture] || []
          patterns = conv[:patterns] || []

          if architecture.any? || patterns.any?
            lines << "## Architecture hints"
            architecture.first(5).each { |item| lines << "- #{item}" }
            patterns.first(5).each { |item| lines << "- #{item}" }
            lines << ""
          end
        end

        lines << "## MCP tool reference"
        lines << "- `rails_get_schema(detail:\"summary\")` to inspect tables first."
        lines << "- `rails_get_model_details(model:\"User\")` for model-level detail."
        lines << "- `rails_get_routes(detail:\"summary\")` before editing controllers or endpoints."
        lines << "- `rails_get_controllers(controller:\"UsersController\")` for filters and params."
        lines << "- `rails_get_config` and `rails_get_conventions` for stack decisions."
        lines << "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)` for targeted searches."
        lines << ""
        lines << "## Codex notes"
        lines << "- This repository also includes `.mcp.json` for MCP client setup."
        lines << "- See `.codex/README.md` for optional local Codex setup guidance."
        lines << ""

        lines.join("\n")
      end

      def append_compact_codex_models_section(lines, models)
        lines << "## Key models"
        unless models.is_a?(Hash) && !models[:error] && models.any?
          lines << "- Use `rails_get_model_details(detail:\"summary\")` to discover models."
          lines << ""
          return
        end

        limit = RailsAiContext.configuration.codex_compact_model_list_limit.to_i
        if limit <= 0
          lines << "- _Use `rails_get_model_details(detail:\"summary\")` for names — not listed here to save context._"
        else
          models.keys.sort.first(limit).each do |name|
            data = models[name]
            assocs = (data[:associations] || []).first(2).map { |a| "#{a[:type]} :#{a[:name]}" }.join(", ")
            line = "- #{name}"
            line += " — #{assocs}" unless assocs.empty?
            lines << line
          end
          remainder = models.size - limit
          lines << "- ...#{remainder} more — `rails_get_model_details(detail:\"summary\")`." if remainder.positive?
        end
        lines << ""
      end
    end

    # Full-context Codex instructions: same sections as {MarkdownSerializer}, with Codex-specific header/footer.
    #
    # @since 0.8.0
    class FullCodexSerializer < MarkdownSerializer
      private

      def header
        <<~MD
          # #{context[:app_name]} — Codex Instructions

          > Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}
          > Auto-generated by rails-ai-context v#{RailsAiContext::VERSION}

          Codex reads AGENTS.md before starting work. Use this file as the
          project-level instruction source for repository-specific guidance.
        MD
      end

      def footer
        <<~MD
          ---
          _Auto-generated. Run `rails ai:context:codex` to regenerate._
        MD
      end
    end
  end
end
