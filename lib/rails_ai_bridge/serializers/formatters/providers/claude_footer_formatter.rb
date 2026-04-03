# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Claude Code footer with behavioral rules and regeneration note.
      class ClaudeFooterFormatter < Base
        # @return [String]
        def call
          arch = context.dig(:conventions, :architecture)
          arch_summary = arch&.any? ? arch.join(", ") : nil

          lines = [
            "## Behavioral Rules",
            "",
            "When working in this codebase:",
            "- Follow existing patterns and conventions detected above",
            "- Use the database schema as the source of truth for column names and types",
            "- Respect existing associations and validations when modifying models"
          ]
          lines << "- Match the project's architecture style (#{arch_summary})" if arch_summary
          lines << "- Run `#{ContextSummary.test_command(context)}` after making changes to verify correctness"
          lines << ""
          lines << "---"
          lines << "_This context file is auto-generated. Run `rails ai:bridge` to regenerate._"
          lines.join("\n")
        end
      end
    end
  end
end
