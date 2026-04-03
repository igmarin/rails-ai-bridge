# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Action Text section with RichText models.
      #
      # @see Formatters::Providers::SectionFormatter
      class ActionTextFormatter < Formatters::Providers::SectionFormatter
        section :action_text

        private

        def render(data)
          return unless data[:models]&.any?

          lines = [ "## Action Text" ]
          data[:models].each { |m| lines << "- `#{m}`" }
          lines.join("\n")
        end
      end
    end
  end
end
