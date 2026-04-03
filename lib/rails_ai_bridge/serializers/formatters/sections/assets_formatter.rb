# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Asset Pipeline section.
      #
      # @see Formatters::Providers::SectionFormatter
      class AssetsFormatter < Formatters::Providers::SectionFormatter
        section :assets

        private

        def render(data)
          return unless data[:precompiler] || data[:js_bundler] || data[:css_framework]

          lines = [ "## Asset Pipeline", "" ]
          lines << "- **Precompiler:** `#{data[:precompiler]}`" if data[:precompiler]
          lines << "- **JavaScript bundler:** `#{data[:js_bundler]}`" if data[:js_bundler]
          if data[:importmap_pins]&.any?
            lines << "  - Importmap pins: #{data[:importmap_pins].map { |p| "`#{p}`" }.join(", ")}"
          end
          lines << "- **CSS framework:** `#{data[:css_framework]}`" if data[:css_framework]
          lines << "- **Manifest files:** `#{data[:manifest_files].join(", ")}`" if data[:manifest_files]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
