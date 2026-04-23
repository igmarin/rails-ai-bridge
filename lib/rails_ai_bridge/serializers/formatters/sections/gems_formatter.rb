# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Gems section.
      #
      # @see Formatters::Providers::SectionFormatter
      class GemsFormatter < SectionFormatter
        section :gems

        private

        def render(data)
          return unless data[:total_gems]

          lines = ['## Gems', '']
          lines << "- Total gems: `#{data[:total_gems]}`"
          if data[:notable_gems]&.any?
            lines << ''
            lines << '### Notable Gems'
            data[:notable_gems].sort_by { |g| [g[:category], g[:name]] }.each do |g|
              lines << "- `#{g[:name]}` (`#{g[:version]}`): #{g[:note]}"
            end
          end
          lines.join("\n")
        end
      end
    end
  end
end
