# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Codex-specific document footer with regeneration instructions.
      class CodexFooterFormatter < Base
        # @return [String]
        def call
          RegenerationFooter.markdown(command: "rails ai:bridge:codex", variant: :auto_short)
        end
      end
    end
  end
end
