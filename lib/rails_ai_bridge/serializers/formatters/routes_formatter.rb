# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Routes section grouped by controller.
      class RoutesFormatter < Base
        # @return [String, nil]
        def call
          routes = context[:routes]
          return unless routes
          return if routes[:error]

          lines = [ "## Routes (#{routes[:total_routes]} total)" ]
          routes[:by_controller]&.sort&.each do |ctrl, actions|
            lines << "### #{ctrl}"
            actions.each do |r|
              lines << "- `#{r[:verb]} #{r[:path]}` → #{r[:action]}"
            end
          end
          lines.join("\n")
        end
      end
    end
  end
end
