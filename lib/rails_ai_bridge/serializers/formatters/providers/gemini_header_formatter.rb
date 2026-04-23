# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Gemini-specific document header.
      class GeminiHeaderFormatter < Base
        # Renders the header for the GEMINI.md file.
        #
        # @return [String] The rendered header.
        def call
          ProviderDocumentHeader.call(
            context: context,
            document_title: 'AI Context',
            layout: :ai_context,
            intro: <<~INTRO.chomp
              This file provides a high-level overview of this Rails application's
              structure, patterns, and conventions. As an AI assistant, use this context
              to quickly understand the project and generate idiomatic code that
              adheres to its design decisions. For deeper dives, use the live
              MCP tools referenced throughout this document.
            INTRO
          )
        end
      end
    end
  end
end
