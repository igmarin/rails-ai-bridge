# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the document footer with regeneration instructions.
      class FooterFormatter < Formatters::Base
        # @return [String]
        def call
          <<~MD
            ---
            _This context file is auto-generated. Run `rails ai:bridge` to regenerate._
          MD
        end
      end
    end
  end
end
