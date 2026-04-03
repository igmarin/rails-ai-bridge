# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the Codex-specific document footer with regeneration instructions.
      class CodexFooterFormatter < Formatters::Base
        # @return [String]
        def call
          <<~MD
            ---
            _Auto-generated. Run `rails ai:bridge:codex` to regenerate._
          MD
        end
      end
    end
  end
end
