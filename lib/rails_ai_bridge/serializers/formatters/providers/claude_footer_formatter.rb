# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Claude Code footer with behavioral rules and regeneration note.
      class ClaudeFooterFormatter < Base
        # @see RailsAiBridge::Serializers::SharedAssistantGuidance.claude_full_footer_lines
        # @return [String]
        def call
          SharedAssistantGuidance.claude_full_footer_lines(context).join("\n")
        end
      end
    end
  end
end
