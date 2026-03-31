# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Internationalization section with locale settings.
      class I18nFormatter < Base
        # @return [String, nil]
        def call
          data = context[:i18n]
          return unless data
          return if data[:error]

          lines = [ "## Internationalization" ]
          lines << "- Default locale: #{data[:default_locale]}"
          lines << "- Available locales: #{data[:available_locales]&.join(', ')}"
          lines << "- Locale files: #{data[:total_locale_files]}" if data[:total_locale_files]&.positive?
          lines.join("\n")
        end
      end
    end
  end
end
