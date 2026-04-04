# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the project rules document footer for .cursorrules full mode.
      class RulesFooterFormatter < Base
        # @return [String]
        def call
          RegenerationFooter.markdown(command: "rails ai:bridge", variant: :auto_branded)
        end
      end
    end
  end
end
