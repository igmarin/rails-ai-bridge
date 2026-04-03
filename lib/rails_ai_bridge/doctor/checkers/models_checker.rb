# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class ModelsChecker < BaseChecker
        def call
          models_path = File.join(app.root, "app/models", "**/*.rb")
          models = Dir.glob(models_path)

          check(
            "Models",
            models.any?,
            pass: { message: "#{models.size} model files found" },
            fail: { status: :warn, message: "No model files found in app/models/", fix: "Generate models with `rails generate model`" }
          )
        end
      end
    end
  end
end
