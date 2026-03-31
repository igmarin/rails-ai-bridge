# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the project rules document header for .cursorrules full mode.
      class RulesHeaderFormatter < Base
        # @return [String]
        def call
          <<~MD
            # #{context[:app_name]} — Project Rules

            Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}
          MD
        end
      end
    end
  end
end
