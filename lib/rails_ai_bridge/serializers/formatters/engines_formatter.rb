# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Mounted Engines section.
      class EnginesFormatter < SectionFormatter
        section :engines

        private

        def render(data)
          lines = [ "## Mounted Engines" ]
          if data[:mounted_engines]&.any?
            data[:mounted_engines].each do |e|
              desc = e[:description] ? " — #{e[:description]}" : ""
              lines << "- `#{e[:engine]}` at `#{e[:path]}`#{desc}"
            end
          else
            lines << "- No mounted engines"
          end
          lines.join("\n")
        end
      end
    end
  end
end
