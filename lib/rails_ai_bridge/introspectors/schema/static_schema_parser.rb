# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    module Schema
      # Parses a +db/schema.rb+ file as plain text, without a live database
      # connection.
      #
      # Each instance is single-use: construct it with the file content and a
      # configuration object, call {#call}, and discard. No mutable state
      # escapes the instance.
      #
      # == Supported schema DSL lines
      #
      # * +create_table "name"+ — opens a table context
      # * +t.<type> "name"+ — adds a column to the current table
      # * +add_index "table", "col"+ or +add_index "table", ["col"]+ — adds an
      #   index entry to the named table
      #
      # Internal Rails tables (+ar_internal_metadata+, +schema_migrations+) and
      # any table matching {Config::Introspection#excluded_tables} are silently
      # skipped.
      #
      # @example
      #   content = File.read("db/schema.rb")
      #   result  = StaticSchemaParser.new(content: content, config: RailsAiBridge.configuration).call
      #   # => { adapter: "static_parse", tables: { ... }, total_tables: N, note: "..." }
      #
      # @see RailsAiBridge::Introspectors::SchemaIntrospector
      class StaticSchemaParser
        # Regex matching a +create_table+ declaration line.
        TABLE_LINE   = /create_table\s+"(\w+)"/

        # Regex matching a column definition inside a table block (+t.<type> "name"+).
        COLUMN_LINE  = /t\.(\w+)\s+"(\w+)"/

        # Regex matching an +add_index+ statement (bare or array column form).
        # Only the first column is captured for multi-column indexes — sufficient
        # for context output but not a complete representation.
        INDEX_LINE   = /add_index\s+"(\w+)",\s+\[?"(\w+)"/

        # Rails-managed tables that must never appear in introspection output.
        INTERNAL_TABLES = %w[ar_internal_metadata schema_migrations].freeze

        # @param content [String] full text of +db/schema.rb+
        # @param config  [RailsAiBridge::Config::Introspection, RailsAiBridge::Configuration]
        #   any object that responds to +#excluded_table?+
        def initialize(content:, config:)
          @content       = content
          @config        = config
          @tables        = {}
          @current_table = nil
        end

        # Parse the schema content and return the tables hash.
        #
        # @return [Hash{Symbol => Object}] with keys +:adapter+, +:tables+,
        #   +:total_tables+, and +:note+
        def call
          @content.each_line do |line|
            next if parse_table_line?(line)
            next if parse_column_line?(line)

            parse_index_line?(line)
          end

          {
            adapter: 'static_parse',
            tables: @tables,
            total_tables: @tables.size,
            note: 'Parsed from db/schema.rb (no DB connection)'
          }
        end

        private

        # Detects a +create_table+ line and opens a new table context.
        # Sets +@current_table+ to +nil+ when the table should be skipped.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_table_line?(line)
          match = TABLE_LINE.match(line)
          return false unless match

          name = match[1]
          @current_table = skip_table?(name) ? nil : name
          @tables[@current_table] = { columns: [], indexes: [], foreign_keys: [] } if @current_table
          true
        end

        # Detects a column definition and appends it to the current table.
        # No-ops when there is no active table context.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_column_line?(line)
          return false unless @current_table

          match = COLUMN_LINE.match(line)
          return false unless match

          @tables[@current_table][:columns] << { name: match[2], type: match[1] }
          true
        end

        # Detects an +add_index+ statement and appends an index entry to the
        # matching table. No-ops when the table is not present in +@tables+.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_index_line?(line)
          match = INDEX_LINE.match(line)
          return false unless match

          @tables[match[1]]&.dig(:indexes)&.push({ columns: match[2] })
          true
        end

        # Returns +true+ when +name+ is an internal Rails table or is excluded
        # by the current configuration.
        #
        # @param name [String]
        # @return [Boolean]
        def skip_table?(name)
          INTERNAL_TABLES.any? { |t| name.start_with?(t) } ||
            @config.excluded_table?(name)
        end
      end
    end
  end
end
