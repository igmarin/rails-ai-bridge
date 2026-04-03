# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class MigrationsChecker < BaseChecker
        def call
          migrations_path = File.join(app.root, "db/migrate", "*.rb")
          migrations = Dir.glob(migrations_path)

          check(
            "Migrations",
            migrations.any?,
            pass: { message: "#{migrations.size} migration files found" },
            fail: { status: :warn, message: "No migrations found in db/migrate/", fix: "Run `rails generate migration` to create one" }
          )
        end
      end
    end
  end
end
