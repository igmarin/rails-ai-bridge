# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class SchemaChecker < BaseChecker
        def call
          schema_path = File.join(app.root, "db/schema.rb")
          check(
            "Schema",
            File.exist?(schema_path),
            pass: { message: "db/schema.rb found" },
            fail: { status: :warn, message: "db/schema.rb not found", fix: "Run `rails db:schema:dump` to generate it" }
          )
        end
      end
    end
  end
end
