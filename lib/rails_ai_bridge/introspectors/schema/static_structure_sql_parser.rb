# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    module Schema
      # Parses a +db/structure.sql+ file as plain text, without a live database
      # connection. This is the +schema_format = :sql+ counterpart to
      # {StaticSchemaParser}: apps that keep their schema as SQL (common on
      # Postgres, where +schema.rb+ cannot represent partitions, views,
      # extensions, or custom SQL) have no +db/schema.rb+ to fall back to in
      # offline environments (CI, Claude Code, agent contexts).
      #
      # Each instance is single-use: construct it with the file content and a
      # configuration object, call {#call}, and discard. No mutable state
      # escapes the instance.
      #
      # == Supported DDL (pg_dump / structure.sql form)
      #
      # * +CREATE TABLE [IF NOT EXISTS] [schema.]name (+ — opens a table context
      # * +<name> <type> ...+ — a column line inside the table body; the leading
      #   identifier is the column and the remainder (minus +NOT NULL+/+DEFAULT+)
      #   is the SQL type. Table-level constraint lines (+CONSTRAINT+,
      #   +PRIMARY KEY+, +FOREIGN KEY+, …) are skipped.
      # * +);+ — closes the current table context
      # * +CREATE [UNIQUE] INDEX name ON [schema.]table USING method (cols)+ —
      #   adds an index entry (first column only) to the named table
      #
      # Foreign keys are intentionally left empty to match {StaticSchemaParser};
      # the live {SchemaIntrospector} path reports them in full.
      #
      # Internal Rails tables (+ar_internal_metadata+, +schema_migrations+) and
      # any table matching {Config::Introspection#excluded_tables} are silently
      # skipped.
      #
      # @example
      #   content = File.read("db/structure.sql")
      #   result  = StaticStructureSqlParser.new(content: content, config: RailsAiBridge.configuration).call
      #   # => { adapter: "static_parse", tables: { ... }, total_tables: N, note: "..." }
      #
      # @see RailsAiBridge::Introspectors::SchemaIntrospector
      # @see RailsAiBridge::Introspectors::Schema::StaticSchemaParser
      class StaticStructureSqlParser
        # Regex matching a +CREATE TABLE+ declaration, tolerating +IF NOT EXISTS+,
        # a schema qualifier (+public.+), and optional quoting of either part.
        TABLE_LINE = /\ACREATE TABLE (?:IF NOT EXISTS\s+)?(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s*\(/

        # Regex matching the end of a table body (+);+ at column zero).
        TABLE_END_LINE = /\A\)/

        # Regex matching a column definition inside a table body: leading
        # whitespace, an identifier (optionally quoted), then the type/modifiers.
        COLUMN_LINE = /\A\s+"?([A-Za-z_]\w*)"?\s+(.+)/

        # Regex matching a +CREATE INDEX+ statement. Captures the target table
        # and the raw parenthesised column list; only the first column is kept
        # (parity with {StaticSchemaParser}).
        INDEX_LINE = /\ACREATE\s+(?:UNIQUE\s+)?INDEX\s+.+?\s+ON\s+(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s+(?:USING\s+\w+\s+)?\(([^)]+)\)/

        # Rails-managed tables that must never appear in introspection output.
        INTERNAL_TABLES = %w[ar_internal_metadata schema_migrations].freeze

        # Table-level constraint keywords that share a column line's shape but
        # are not columns.
        CONSTRAINT_KEYWORDS = %w[CONSTRAINT PRIMARY FOREIGN UNIQUE CHECK EXCLUDE LIKE DEFERRABLE].freeze

        # @param content [String] full text of +db/structure.sql+
        # @param config  [RailsAiBridge::Config::Introspection, RailsAiBridge::Configuration]
        #   any object that responds to +#excluded_table?+
        def initialize(content:, config:)
          @content       = content
          @config        = config
          @tables        = {}
          @current_table = nil
          @in_table      = false
        end

        # Parse the structure.sql content and return the tables hash.
        #
        # @return [Hash{Symbol => Object}] with keys +:adapter+, +:tables+,
        #   +:total_tables+, and +:note+
        def call
          @content.each_line do |line|
            if @in_table
              parse_body_line(line)
            else
              next if parse_table_line?(line)

              parse_index_line?(line)
            end
          end

          {
            adapter: 'static_parse',
            tables: @tables,
            total_tables: @tables.size,
            note: 'Parsed from db/structure.sql (no DB connection)'
          }
        end

        private

        # Opens a table context on a +CREATE TABLE+ line. Sets +@current_table+
        # to +nil+ for skipped tables while still tracking that we are inside a
        # body, so the closing +);+ is honoured.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_table_line?(line)
          match = TABLE_LINE.match(line)
          return false unless match

          name = match[1]
          @in_table = true
          @current_table = skip_table?(name) ? nil : name
          @tables[@current_table] = { columns: [], indexes: [], foreign_keys: [] } if @current_table
          true
        end

        # Handles a line while inside a table body: either the closing paren or a
        # column definition (constraint lines are ignored).
        #
        # @param line [String]
        # @return [void]
        def parse_body_line(line)
          if TABLE_END_LINE.match?(line)
            @in_table = false
            @current_table = nil
            return
          end

          parse_column_line(line) if @current_table
        end

        # Appends a column to the current table unless the line is a table-level
        # constraint.
        #
        # @param line [String]
        # @return [void]
        def parse_column_line(line)
          match = COLUMN_LINE.match(line)
          return unless match
          return if constraint_keyword?(match[1])

          @tables[@current_table][:columns] << { name: match[1], type: normalize_type(match[2]) }
        end

        # Adds an index entry (first column only) to the matching table. No-ops
        # when the table is not present in +@tables+.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_index_line?(line)
          match = INDEX_LINE.match(line)
          return false unless match

          column = first_index_column(match[2])
          @tables[match[1]]&.dig(:indexes)&.push({ columns: column }) if column
          true
        end

        # Strips a trailing comma and the +DEFAULT ...+ / +NOT NULL+ / +NULL+
        # modifiers to leave the bare SQL type.
        #
        # @param raw [String] everything after the column name
        # @return [String] the SQL type (e.g. +"character varying"+, +"bigint"+)
        def normalize_type(raw)
          raw.strip
             .sub(/,\s*\z/, '')
             .sub(/\s+DEFAULT\b.*\z/i, '')
             .sub(/\s+NOT\s+NULL\s*\z/i, '')
             .sub(/\s+NULL\s*\z/i, '')
             .strip
        end

        # Extracts the first column identifier from an index's parenthesised
        # column list, dropping opclasses (+col varchar_pattern_ops+) and
        # expression noise.
        #
        # @param columns [String] raw text between the index parentheses
        # @return [String, nil]
        def first_index_column(columns)
          columns.split(',').first&.slice(/[A-Za-z_]\w*/)
        end

        # @param name [String]
        # @return [Boolean] +true+ when +name+ is a table-level constraint keyword
        def constraint_keyword?(name)
          CONSTRAINT_KEYWORDS.include?(name.upcase)
        end

        # @param name [String]
        # @return [Boolean] +true+ when +name+ is internal or excluded by config
        def skip_table?(name)
          INTERNAL_TABLES.any? { |t| name.start_with?(t) } ||
            @config.excluded_table?(name)
        end
      end
    end
  end
end
