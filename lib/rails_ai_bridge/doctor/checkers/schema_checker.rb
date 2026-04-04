# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +db/schema.rb+ exists for schema-driven AI context.
      class SchemaChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when the schema file exists; +:warn+ otherwise
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
