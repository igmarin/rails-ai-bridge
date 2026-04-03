# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Formats full view details including templates, partials, helpers, and components.
      class FullFormatter < BaseFormatter
        # @return [String] The formatted full output.
        def call
          filtered = filter_view_data
          return "View introspection failed: #{filtered[:error]}" if filtered[:error]

          lines = [ StandardFormatter.new(context: @context, controller: @controller, partial: @partial).call ]

          if filtered[:helpers].any?
            lines << "" << "## Helpers"
            filtered[:helpers].each do |helper|
              methods = Array(helper[:methods]).join(", ")
              lines << "- `#{helper[:file]}`: #{methods}"
            end
          end

          if filtered[:view_components].any?
            lines << "" << "## View Components"
            filtered[:view_components].each { |component| lines << "- `#{component}`" }
          end

          lines.join("\n")
        end
      end
    end
  end
end
