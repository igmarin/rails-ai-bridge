# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class I18nChecker < BaseChecker
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
