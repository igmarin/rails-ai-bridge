# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +config/locales+ contains YAML locale files.
      class I18nChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when locale files exist; +:warn+ otherwise
        def call
          locales_path = File.join(app.root, "config/locales", "**/*.{yml,yaml}")
          locales = Dir.glob(locales_path)

          check(
            "I18n",
            locales.any?,
            pass: { message: "#{locales.size} locale files found" },
            fail: { status: :warn, message: "No locale files found in config/locales/", fix: "Add locale files for internationalization support" }
          )
        end
      end
    end
  end
end
