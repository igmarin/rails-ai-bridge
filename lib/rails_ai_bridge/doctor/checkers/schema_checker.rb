# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies a schema file exists for schema-driven AI context. Accepts
      # either +db/schema.rb+ (+schema_format = :ruby+) or +db/structure.sql+
      # (+schema_format = :sql+).
      class SchemaChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when a schema file exists; +:warn+ otherwise
        def call
          check(
            'Schema',
            present_schema_file,
            pass: { message: "#{present_schema_file} found" },
            fail: {
              status: :warn,
              message: 'db/schema.rb or db/structure.sql not found',
              fix: 'Run `rails db:migrate` (or `db:schema:dump`) to generate one'
            }
          )
        end

        private

        # @return [String, nil] the schema file that exists (schema.rb preferred), or +nil+
        def present_schema_file
          %w[db/schema.rb db/structure.sql].find { |rel| File.exist?(File.join(app.root, rel)) }
        end
      end
    end
  end
end
