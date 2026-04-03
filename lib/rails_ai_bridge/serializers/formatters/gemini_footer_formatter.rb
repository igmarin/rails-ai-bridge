# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Gemini footer with behavioral rules and regeneration note.
      class GeminiFooterFormatter < Base
        # Renders the footer for the GEMINI.md file.
        #
        # @return [String] The rendered footer.
        def call
          arch = context.dig(:conventions, :architecture)
          arch_summary = arch&.any? ? arch.join(", ") : nil

          lines = [
            "## Behavioral Rules",
            "",
            "- **Adhere to Conventions:** Strictly follow the existing patterns and conventions outlined in this document.",
            "- **Schema as Source of Truth:** Always use the database schema as the definitive source for column names, types, and relationships.",
            "- **Respect Existing Logic:** Ensure all new code respects existing associations, validations, and service objects.",
            "- **Write Tests:** All new features and bug fixes must be accompanied by corresponding tests."
          ]
          lines << "- **Match Architecture:** Align with the project's architectural style (#{arch_summary})." if arch_summary
          lines << "- **Verify Correctness:** Run `#{ContextSummary.test_command(context)}` and `bundle exec rubocop` after making changes to ensure correctness and style adherence."
          lines << ""
          lines << "---"
          lines << "_This context file is auto-generated. Run `rails ai:bridge` to regenerate._"
          lines.join("\n")
        end
      end
    end
  end
end
