# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Copilot Instructions document header.
      class CopilotHeaderFormatter < Base
        # @return [String]
        def call
          ProviderDocumentHeader.call(
            context: context,
            document_title: "Copilot Instructions",
            layout: :instructions,
            intro: "Use this context to generate code that fits this project's structure and patterns."
          )
        end
      end
    end
  end
end
