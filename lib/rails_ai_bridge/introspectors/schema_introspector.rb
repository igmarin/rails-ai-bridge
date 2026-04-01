# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts database schema information — tables, columns, indexes, and
    # foreign keys — from a live ActiveRecord connection when available, or by
    # falling back to text-parsing +db/schema.rb+ via
    # {Schema::StaticSchemaParser} when no connection is present (CI, Claude
    # Code, offline environments).
    #
    # @see Schema::StaticSchemaParser
    class SchemaIntrospector
      # @return [Rails::Application]
      attr_reader :app

      # @return [RailsAiBridge::Configuration]
      attr_reader :config

      # @param app [Rails::Application]
      def initialize(app)
        @app    = app
        @config = RailsAiBridge.configuration
      end

      # Returns database schema context. Uses a live connection when available;
      # falls back to static text-parsing otherwise.
      #
      # @return [Hash{Symbol => Object}] includes +:adapter+, +:tables+,
      #   +:total_tables+, and +:schema_version+ (live) or +:note+ (static)
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
      rescue StandardError
        false
      end

      def adapter_name
        ActiveRecord::Base.connection.adapter_name
      rescue StandardError
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
      rescue StandardError
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

      # Fallback: parse db/schema.rb as text when the DB is not connected.
      # Delegates all parsing to {Schema::StaticSchemaParser}.
      #
      # @return [Hash] parsed schema result, or +{ error: }+ when the file is absent
      def static_schema_parse
        path = schema_file_path
        return { error: "No schema.rb found at #{path}" } unless File.exist?(path)

        Schema::StaticSchemaParser.new(content: File.read(path), config: config).call
      end
    end
  end
end
