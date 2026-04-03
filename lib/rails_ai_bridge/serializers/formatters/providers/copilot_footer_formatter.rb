# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Copilot-specific document footer.
      class CopilotFooterFormatter < Base
        # @return [String]
        def call
          <<~MD
            ---
            _Auto-generated. Run `rails ai:bridge` to regenerate._
          MD
        end
      end
    end
  end
end
