# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Internationalization (I18n) section.
      #
      # @see Formatters::Providers::SectionFormatter
      class I18nFormatter < Formatters::Providers::SectionFormatter
        section :i18n

        private

        def render(data)
          return unless data[:locales]&.any?

          lines = [ "## Internationalization (I18n)" ]
          lines << "- Locales: #{data[:locales].map { |l| "`#{l}`" }.join(", ")}"
          lines.join("\n")
        end
      end
    end
  end
end
