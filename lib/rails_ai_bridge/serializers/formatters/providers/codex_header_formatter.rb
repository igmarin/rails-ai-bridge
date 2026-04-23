# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Codex (AGENTS.md) document header.
      class CodexHeaderFormatter < Base
        # @return [String]
        def call
          ProviderDocumentHeader.call(
            context: context,
            document_title: 'Codex Instructions',
            layout: :instructions,
            intro: <<~INTRO.chomp
              Codex reads AGENTS.md before starting work. Use this file as the
              project-level instruction source for repository-specific guidance.
            INTRO
          )
        end
      end
    end
  end
end
