# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Routes section grouped by controller.
      #
      # @see Formatters::Providers::SectionFormatter
      class RoutesFormatter < SectionFormatter
        section :routes

        private

        def render(data)
          lines = ["## Routes (#{data[:total_routes]} total)"]
          data[:by_controller]&.sort&.each do |ctrl, actions|
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
