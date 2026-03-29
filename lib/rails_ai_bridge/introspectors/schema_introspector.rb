# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts database schema information including tables, columns,
    # indexes, and foreign keys from the Rails application.
    class SchemaIntrospector
      attr_reader :app, :config

      def initialize(app)
        @app    = app
        @config = RailsAiBridge.configuration
      end

      # @return [Hash] database schema context
      def call
        return static_schema_parse unless active_record_connected?

        {
          adapter: adapter_name,
          tables: extract_tables,
          total_tables: table_names.size,
          schema_version: current_schema_version
        }
      end

      private

      def active_record_connected?
        defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      rescue
        false
      end

      def adapter_name
        ActiveRecord::Base.connection.adapter_name
      rescue
        "unknown"
      end

      def connection
        ActiveRecord::Base.connection
      end

      def table_names
        @table_names ||= begin
          names = connection.tables.reject { |t| t.start_with?("ar_internal_metadata", "schema_migrations") }
          names.reject { |t| config.excluded_table?(t) }
        end
      end

      def extract_tables
        table_names.each_with_object({}) do |table, hash|
          hash[table] = {
            columns: extract_columns(table),
            indexes: extract_indexes(table),
            foreign_keys: extract_foreign_keys(table),
            primary_key: connection.primary_key(table)
          }
        end
      end

      def extract_columns(table)
        connection.columns(table).map do |col|
          {
            name: col.name,
            type: col.type.to_s,
            null: col.null,
            default: col.default,
            limit: col.limit,
            precision: col.precision,
            scale: col.scale,
            comment: col.comment
          }.compact
        end
      end

      def extract_indexes(table)
        connection.indexes(table).map do |idx|
          {
            name: idx.name,
            columns: idx.columns,
            unique: idx.unique,
            where: idx.where
          }.compact
        end
      end

      def extract_foreign_keys(table)
        connection.foreign_keys(table).map do |fk|
          {
            from_table: fk.from_table,
            to_table: fk.to_table,
            column: fk.column,
            primary_key: fk.primary_key,
            on_delete: fk.on_delete,
            on_update: fk.on_update
          }.compact
        end
      rescue
        [] # Some adapters don't support foreign_keys
      end

      def current_schema_version
        if File.exist?(schema_file_path)
          content = File.read(schema_file_path)
          match = content.match(/version:\s*([\d_]+)/)
          match ? match[1].delete("_") : nil
        end
      end

      def schema_file_path
        File.join(app.root, "db", "schema.rb")
      end

      # Fallback: parse db/schema.rb as text when DB isn't connected
      # This enables introspection in CI, Claude Code, etc.
      def static_schema_parse
        path = schema_file_path
        return { error: "No schema.rb found at #{path}" } unless File.exist?(path)

        content = File.read(path)
        tables = {}
        current_table = nil

        content.each_line do |line|
          if (match = line.match(/create_table\s+"(\w+)"/))
            current_table = match[1]
            next if current_table.start_with?("ar_internal_metadata", "schema_migrations")
            tables[current_table] = { columns: [], indexes: [], foreign_keys: [] }
          elsif current_table && (match = line.match(/t\.(\w+)\s+"(\w+)"/))
            tables[current_table][:columns] << { name: match[2], type: match[1] }
          elsif (match = line.match(/add_index\s+"(\w+)",\s+\[?"(\w+)"/))
            tables[match[1]]&.dig(:indexes)&.push({ columns: match[2] })
          end
        end

        {
          adapter: "static_parse",
          tables: tables,
          total_tables: tables.size,
          note: "Parsed from db/schema.rb (no DB connection)"
        }
      end
    end
  end
end
