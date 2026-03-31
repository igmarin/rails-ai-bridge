# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Asset Pipeline section with bundler and CSS framework info.
      class AssetsFormatter < SectionFormatter
        section :assets

        private

        def render(data)
          lines = [ "## Asset Pipeline" ]
          lines << "- Pipeline: #{data[:pipeline]}" if data[:pipeline]
          lines << "- JS bundler: #{data[:js_bundler]}" if data[:js_bundler]
          lines << "- CSS framework: #{data[:css_framework]}" if data[:css_framework]
          lines << "- Importmap pins: #{data[:importmap_pins].join(', ')}" if data[:importmap_pins]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
