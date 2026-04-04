# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the document header with app name, version, and generator metadata.
      class HeaderFormatter < Base
        # @return [String]
        def call
          ProviderDocumentHeader.call(
            context: context,
            document_title: "AI Context",
            layout: :ai_context,
            intro: <<~INTRO.chomp
              This file gives AI assistants (Claude Code, Cursor, Copilot) deep context
              about this Rails application's structure, patterns, and conventions.
            INTRO
          )
        end
      end
    end
  end
end
