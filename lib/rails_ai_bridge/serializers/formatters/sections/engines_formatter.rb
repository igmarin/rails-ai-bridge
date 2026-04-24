# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Rails Engines section.
      #
      # @see Formatters::Providers::SectionFormatter
      class EnginesFormatter < SectionFormatter
        section :engines

        private

        def render(data)
          return unless data[:mounted]&.any?

          lines = ['## Rails Engines', '']
          data[:mounted].each { |e| lines << "- `#{e}`" }
          lines.join("\n")
        end
      end
    end
  end
end
