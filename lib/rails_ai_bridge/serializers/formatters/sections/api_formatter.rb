# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the API Endpoints section based on introspected API details.
      #
      # @see Formatters::Providers::SectionFormatter
      class ApiFormatter < Formatters::Providers::SectionFormatter
        section :api

        private

        def render(data)
          return unless data[:endpoints]&.any?

          lines = [ "## API Endpoints" ]
          lines << "- Version: `#{data[:version]}`" if data[:version]
          lines << "- Base path: `#{data[:base_path]}`" if data[:base_path]
          if data[:documentation_url]
            lines << "- Documentation: [#{data[:documentation_url]}](#{data[:documentation_url]})"
          end
          lines << ""
          lines << "### Endpoints"
          data[:endpoints].each do |endpoint|
            lines << "- `#{endpoint[:verb]} #{endpoint[:path]}`: `#{endpoint[:controller]}##{endpoint[:action]}`"
          end
          lines.join("\n")
        end
      end
    end
  end
end
