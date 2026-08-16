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
      # * +) PARTITION BY method+ / a following +PARTITION BY+ line — marks the
      #   just-closed table as a partitioned parent (+partitioned+, +partition_by+)
      # * +CREATE TABLE [IF NOT EXISTS] [schema.]child PARTITION OF [schema.]parent+
      #   (pg_dump form, no column list) — expands a partition child with
      #   +partition_of+ / +partition_bound+ and inherited parent columns
      # * +) PARTITION OF parent+ / a following +PARTITION OF+ line — attaches
      #   the parent reference to a child that repeated its column list
      # * +FOR VALUES ...+ / +DEFAULT+ — records the partition bound on the
      #   pending child (RANGE / LIST / HASH / default)
      # * +CREATE [UNIQUE] INDEX name ON [schema.]table USING method (cols)+ —
      #   adds an index entry (first simple column) to the named table.
      #   Functional/expression indexes (e.g. +lower(email)+) are skipped.
      # * +ALTER TABLE [ONLY] table ADD CONSTRAINT ... FOREIGN KEY (col)
      #   REFERENCES ref_table (pk)+ — adds a foreign-key entry to +table+
      #   (pg_dump emits these in a separate constraints section).
      #
      # Unlike {StaticSchemaParser} (whose +schema.rb+ static form leaves foreign
      # keys empty), +structure.sql+ spells foreign keys out as parseable DDL, so
      # this parser populates them offline — matching what the live
      # {SchemaIntrospector} path reports.
      #
      # Internal Rails tables (+ar_internal_metadata+, +schema_migrations+) and
      # any table matching {Config::Introspection#excluded_tables} are silently
      # skipped.
      #
      # @example
      #   content = File.read("db/structure.sql")
      #   result  = StaticStructureSqlParser.new(content: content, config: RailsAiBridge.configuration).call
      #   # => { adapter: "static_parse", source: :static, tables: { ... }, total_tables: N, note: "..." }
      #
      # @see RailsAiBridge::Introspectors::SchemaIntrospector
      # @see RailsAiBridge::Introspectors::Schema::StaticSchemaParser
      class StaticStructureSqlParser
        # Regex matching a +CREATE TABLE+ declaration, tolerating +IF NOT EXISTS+,
        # a schema qualifier (+public.+), and optional quoting of either part.
        # Requires an opening paren so +CREATE TABLE … PARTITION OF …+ (no
        # column list) is handled by {PARTITION_OF_LINE} instead.
        TABLE_LINE = /\ACREATE TABLE (?:IF NOT EXISTS\s+)?(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s*\(/

        # Regex matching a pg_dump partition child: +CREATE TABLE child
        # PARTITION OF parent+ with no column list. Captures child, parent, and
        # any trailing bound clause on the same line.
        PARTITION_OF_LINE = /\ACREATE TABLE (?:IF NOT EXISTS\s+)?(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s+PARTITION OF\s+(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s*(.*)/i

        # Regex matching a standalone +PARTITION OF parent+ clause (emitted after
        # a child that repeated its column list).
        PARTITION_OF_CLAUSE = /\APARTITION OF\s+(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s*(.*)/i

        # Regex matching a +PARTITION BY method+ clause on a parent table.
        PARTITION_BY_CLAUSE = /\APARTITION BY\s+(.+)/i

        # Regex matching the end of a table body (+);+ at column zero).
        TABLE_END_LINE = /\A\)/

        # Regex matching a column definition inside a table body: leading
        # whitespace, an identifier (optionally quoted), then the type/modifiers.
        COLUMN_LINE = /\A\s+"?([A-Za-z_]\w*)"?\s+(.+)/

        # Regex matching a +CREATE INDEX+ statement. Captures the target table
        # and the raw parenthesised column list; only the first column is kept
        # (parity with {StaticSchemaParser}).
        INDEX_LINE = /\ACREATE\s+(?:UNIQUE\s+)?INDEX\s+.+?\s+ON\s+(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s+(?:USING\s+\w+\s+)?\(([^)]+)\)/

        # Regex matching an +ALTER TABLE [ONLY] [schema.]table+ statement, which
        # in pg_dump precedes an +ADD CONSTRAINT+ line. Captures the target table.
        ALTER_TABLE_LINE = /\AALTER TABLE (?:ONLY\s+)?(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?/

        # Regex matching an +ADD CONSTRAINT ... FOREIGN KEY (cols) REFERENCES
        # [schema.]ref_table (pk)+ clause. Captures local columns, referenced
        # table, and referenced columns.
        FOREIGN_KEY_LINE = /FOREIGN KEY\s*\(([^)]+)\)\s*REFERENCES\s+(?:[\w"]+\.)?"?([A-Za-z_]\w*)"?\s*\(([^)]+)\)/

        # Regex matching an +ON DELETE <action>+ clause on a foreign-key line.
        ON_DELETE = /ON DELETE ([A-Z ]+?)(?=\s+ON UPDATE|\s+(?:NOT\s+)?(?:DEFERRABLE|VALID)|[,;)]|\z)/i

        # Regex matching an +ON UPDATE <action>+ clause on a foreign-key line.
        ON_UPDATE = /ON UPDATE ([A-Z ]+?)(?=\s+(?:NOT\s+)?(?:DEFERRABLE|VALID)|[,;)]|\z)/i

        # Rails-managed tables that must never appear in introspection output.
        INTERNAL_TABLES = %w[ar_internal_metadata schema_migrations].freeze

        # Table-level constraint keywords that share a column line's shape but
        # are not columns.
        CONSTRAINT_KEYWORDS = %w[CONSTRAINT PRIMARY FOREIGN UNIQUE CHECK EXCLUDE LIKE DEFERRABLE].freeze

        # @param content [String] full text of +db/structure.sql+
        # @param config  [RailsAiBridge::Config::Introspection, RailsAiBridge::Configuration]
        #   any object that responds to +#excluded_table?+
        def initialize(content:, config:)
          @content            = content
          @config             = config
          @tables             = {}
          @current_table      = nil
          @in_table           = false
          @alter_target       = nil
          @pending_partition  = nil
        end

        # Parse the structure.sql content and return the tables hash. Never
        # raises — malformed or non-UTF-8 input is caught and reported as an
        # error hash, per the introspector contract.
        #
        # @return [Hash{Symbol => Object}] with keys +:adapter+, +:source+ (+:static+),
        #   +:tables+, +:total_tables+, and +:note+; or +{ error: }+ on failure
        def call
          @content.each_line { |line| parse_line(line) }

          {
            adapter: 'static_parse',
            source: :static,
            tables: @tables,
            total_tables: @tables.size,
            note: 'Parsed from db/structure.sql (no DB connection)'
          }
        rescue StandardError => error
          { error: "Failed to parse db/structure.sql: #{error.message}" }
        end

        private

        # Dispatches a single line to the table-body handler or the top-level
        # (create/index/alter/foreign-key) handlers.
        #
        # @param line [String]
        # @return [void]
        def parse_line(line)
          return parse_body_line(line) if @in_table
          return if parse_partition_of_line?(line)
          return if parse_table_line?(line)
          return if parse_partition_followup?(line)
          return if parse_index_line?(line)
          return if parse_alter_table_line?(line)

          parse_foreign_key_line?(line)
        end

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
          @pending_partition = nil
          @current_table = skip_table?(name) ? nil : name
          @tables[@current_table] = empty_table_entry if @current_table
          true
        end

        # Expands a pg_dump partition child (+CREATE TABLE child PARTITION OF
        # parent+ with no column list) as a table entry referencing its parent.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_partition_of_line?(line)
          match = PARTITION_OF_LINE.match(line)
          return false unless match

          register_partition_child(name: match[1], parent: match[2], rest: match[3].to_s)
          true
        end

        # Handles a line while inside a table body: either the closing paren or a
        # column definition (constraint lines are ignored). A close without a
        # trailing semicolon (pg_dump parent / column-list child) waits for a
        # following +PARTITION BY+ / +PARTITION OF+ line.
        #
        # @param line [String]
        # @return [void]
        def parse_body_line(line)
          if TABLE_END_LINE.match?(line)
            close_table_body(line)
            return
          end

          parse_column_line(line) if @current_table
        end

        # Closes the current table body and applies any partition clause that
        # shares the closing parenthesis line.
        #
        # @param line [String]
        # @return [void]
        def close_table_body(line)
          table = @current_table
          remainder = line.sub(/\A\)\s*/, '')
          apply_inline_partition_clause(table, remainder) if table && !remainder.empty?

          @in_table = false
          @current_table = nil
          @pending_partition = table if table && line.exclude?(';')
        end

        # Attaches +PARTITION OF+ / +PARTITION BY+ written on the same line as
        # the closing +)+.
        #
        # @param table [String]
        # @param remainder [String] text after the closing parenthesis
        # @return [void]
        def apply_inline_partition_clause(table, remainder)
          stripped = remainder.strip
          if (match = PARTITION_OF_CLAUSE.match(stripped))
            apply_partition_of(table, match[1], match[2].to_s)
          elsif (match = PARTITION_BY_CLAUSE.match(stripped))
            apply_partition_by(table, match[1])
          end
        end

        # Consumes a line that continues a just-closed or just-declared
        # partition statement: +PARTITION BY+, +PARTITION OF+, or the bound
        # (+FOR VALUES …+ / +DEFAULT+). Clears the pending target when the
        # line is unrelated.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line was consumed as a follow-up
        def parse_partition_followup?(line)
          return false unless @pending_partition

          stripped = line.strip
          return true if stripped.empty?

          if (match = PARTITION_OF_CLAUSE.match(stripped))
            apply_partition_of(@pending_partition, match[1], match[2].to_s)
            @pending_partition = nil if stripped.include?(';')
            return true
          end

          if (match = PARTITION_BY_CLAUSE.match(stripped))
            apply_partition_by(@pending_partition, match[1])
            @pending_partition = nil
            return true
          end

          bound = extract_partition_bound(stripped)
          if bound
            apply_partition_bound(@pending_partition, bound)
            @pending_partition = nil
            return true
          end

          @pending_partition = nil
          false
        end

        # Records a partition child and copies the parent's columns when the
        # child declaration has no column list.
        #
        # @param name [String]
        # @param parent [String]
        # @param rest [String] remainder of the CREATE line (bound and/or +;+)
        # @return [void]
        def register_partition_child(name:, parent:, rest:)
          @pending_partition = nil
          return if skip_table?(name)

          @tables[name] = empty_table_entry.merge(
            columns: inherit_columns(parent),
            partition_of: parent
          )
          apply_partition_bound(name, extract_partition_bound(rest))
          @pending_partition = name unless rest.include?(';')
        end

        # Marks +table+ as a partition of +parent+ without replacing columns
        # already parsed from an inline column list.
        #
        # @param table [String]
        # @param parent [String]
        # @param rest [String]
        # @return [void]
        def apply_partition_of(table, parent, rest)
          entry = @tables[table]
          return unless entry

          entry[:partition_of] = parent
          apply_partition_bound(table, extract_partition_bound(rest))
          @pending_partition = table unless rest.include?(';')
        end

        # Marks +table+ as a partitioned parent.
        #
        # @param table [String]
        # @param method [String] raw +PARTITION BY+ argument (e.g. +RANGE (col)+)
        # @return [void]
        def apply_partition_by(table, method)
          entry = @tables[table]
          return unless entry

          entry[:partitioned] = true
          entry[:partition_by] = method.sub(/;\s*\z/, '').strip
        end

        # @param table [String]
        # @param bound [String, nil]
        # @return [void]
        def apply_partition_bound(table, bound)
          return if bound.blank?

          @tables[table][:partition_bound] = bound if @tables[table]
        end

        # Strips a trailing semicolon and keeps +FOR VALUES …+ / +DEFAULT+.
        #
        # @param text [String]
        # @return [String, nil]
        def extract_partition_bound(text)
          cleaned = text.to_s.sub(/;\s*\z/, '').strip
          return nil if cleaned.empty?
          return cleaned if cleaned.match?(/\A(?:FOR VALUES\b|DEFAULT\b)/i)

          nil
        end

        # @param parent [String]
        # @return [Array<Hash>] a copy of the parent's columns, or +[]+
        def inherit_columns(parent)
          columns = @tables.dig(parent, :columns)
          return [] unless columns

          columns.map(&:dup)
        end

        # @return [Hash] empty table payload matching the live introspector shape
        def empty_table_entry
          { columns: [], indexes: [], foreign_keys: [] }
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

        # Records the target table of an +ALTER TABLE+ statement so a following
        # +ADD CONSTRAINT ... FOREIGN KEY+ line can attach to it. Sets
        # +@alter_target+ to +nil+ for skipped/unknown tables.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_alter_table_line?(line)
          match = ALTER_TABLE_LINE.match(line)
          return false unless match

          @alter_target = @tables.key?(match[1]) ? match[1] : nil
          true
        end

        # Appends a foreign-key entry to the current +@alter_target+ table. Mirrors
        # the live introspector's shape (+from_table+, +to_table+, +column+,
        # +primary_key+, +on_delete+, +on_update+), keeping the first column of a
        # composite key for parity with index handling. No-ops without a target.
        #
        # @param line [String]
        # @return [Boolean] +true+ if the line matched
        def parse_foreign_key_line?(line)
          match = FOREIGN_KEY_LINE.match(line)
          return false unless match
          return true unless @alter_target

          @tables[@alter_target][:foreign_keys] << {
            from_table: @alter_target,
            to_table: match[2],
            column: first_identifier(match[1]),
            primary_key: first_identifier(match[3]),
            on_delete: fk_action(line, ON_DELETE),
            on_update: fk_action(line, ON_UPDATE)
          }.compact
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
        # column list. Keeps plain and opclass-qualified columns
        # (+col varchar_pattern_ops+ → +col+) but returns +nil+ for functional
        # or expression indexes (+lower(email)+) so they are skipped rather than
        # mis-attributed to the function name.
        #
        # @param columns [String] raw text between the index parentheses
        # @return [String, nil]
        def first_index_column(columns)
          first = columns.split(',').first&.strip
          return nil if first.nil? || first.include?('(')

          first.slice(/[A-Za-z_]\w*/)
        end

        # Returns the first identifier from a (possibly composite) column list.
        #
        # @param columns [String] comma-separated column list
        # @return [String, nil]
        def first_identifier(columns)
          columns.split(',').first&.slice(/[A-Za-z_]\w*/)
        end

        # Extracts a normalized foreign-key referential action (e.g. +CASCADE+,
        # +SET NULL+) from a line, or +nil+ when the clause is absent.
        #
        # @param line [String]
        # @param pattern [Regexp] {ON_DELETE} or {ON_UPDATE}
        # @return [String, nil]
        def fk_action(line, pattern)
          match = pattern.match(line)
          match && match[1].strip.squeeze(' ').upcase
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
