# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Renders the document footer with regeneration instructions.
      class FooterFormatter < Base
        # @return [String]
        def call
          RegenerationFooter.markdown(command: "rails ai:bridge", variant: :context_file)
        end
      end
    end
  end
end
