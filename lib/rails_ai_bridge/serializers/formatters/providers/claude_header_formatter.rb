# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Claude Code-specific document header.
      class ClaudeHeaderFormatter < Base
        # @return [String]
        def call
          ProviderDocumentHeader.call(
            context: context,
            document_title: 'AI Context',
            layout: :ai_context,
            intro: <<~INTRO.chomp
              This file gives Claude Code deep context about this Rails application's
              structure, patterns, and conventions. Use it to write idiomatic code
              that matches this project's style.
            INTRO
          )
        end
      end
    end
  end
end
