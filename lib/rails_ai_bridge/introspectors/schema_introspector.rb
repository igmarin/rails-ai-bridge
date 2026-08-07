# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts database schema information — tables, columns, indexes, and
    # foreign keys — from a live ActiveRecord connection when available, or by
    # text-parsing the schema file when no connection is present (CI, Claude
    # Code, offline environments). The static fallback prefers +db/schema.rb+
    # ({Schema::StaticSchemaParser}) and falls back to +db/structure.sql+
    # ({Schema::StaticStructureSqlParser}) for +schema_format = :sql+ apps.
    #
    # @see Schema::StaticSchemaParser
    # @see Schema::StaticStructureSqlParser
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
        'unknown'
      end

      def connection
        ActiveRecord::Base.connection
      end

      def table_names
        @table_names ||= begin
          names = connection.tables.reject { |t| t.start_with?('ar_internal_metadata', 'schema_migrations') }
          names.reject { |t| config.excluded_table?(t) }
        end
      end

      def extract_tables
        table_names.index_with do |table|
          {
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
        return unless File.exist?(schema_file_path)

        content = File.read(schema_file_path)
        match = content.match(/version:\s*([\d_]+)/)
        match ? match[1].delete('_') : nil
      end

      def schema_file_path
        File.join(app.root, 'db', 'schema.rb')
      end

      def structure_sql_path
        File.join(app.root, 'db', 'structure.sql')
      end

      # Fallback used when the DB is not connected. Prefers +db/schema.rb+
      # (Ruby DSL) and falls back to +db/structure.sql+ (raw SQL) so
      # +schema_format = :sql+ apps still get schema context offline.
      #
      # @return [Hash] parsed schema result, or +{ error: }+ when neither file exists
      def static_schema_parse
        if File.exist?(schema_file_path)
          Schema::StaticSchemaParser.new(content: File.read(schema_file_path), config: config).call
        elsif File.exist?(structure_sql_path)
          Schema::StaticStructureSqlParser.new(content: File.read(structure_sql_path), config: config).call
        else
          { error: "No db/schema.rb or db/structure.sql found in #{File.join(app.root, 'db')}" }
        end
      rescue StandardError => error
        # Guards the exist?/read race (file removed between check and read) and
        # any other read failure, honouring the introspector never-raise contract.
        { error: "Failed to read schema file: #{error.message}" }
      end
    end
  end
end
