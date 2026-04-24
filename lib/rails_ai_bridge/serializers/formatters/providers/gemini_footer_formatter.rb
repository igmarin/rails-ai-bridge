# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Gemini footer with behavioral rules and regeneration note.
      #
      # @see RailsAiBridge::Serializers::SharedAssistantGuidance.compact_engineering_rules_footer_lines
      class GeminiFooterFormatter < Base
        # Renders the footer for the GEMINI.md file.
        #
        # @return [String] The rendered footer.
        def call
          SharedAssistantGuidance.compact_engineering_rules_footer_lines(
            context,
            rules_heading: '## Behavioral Rules'
          ).join("\n")
        end
      end
    end
  end
end
