# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the project rules document header for .cursorrules full mode.
      class RulesHeaderFormatter < Base
        # @return [String]
        def call
          ProviderDocumentHeader.rules_banner(context: context)
        end
      end
    end
  end
end
