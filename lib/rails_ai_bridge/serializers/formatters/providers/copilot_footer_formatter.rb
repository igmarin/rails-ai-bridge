# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Copilot-specific document footer.
      class CopilotFooterFormatter < Base
        # @return [String]
        def call
          RegenerationFooter.markdown(command: 'rails ai:bridge', variant: :auto_short)
        end
      end
    end
  end
end
