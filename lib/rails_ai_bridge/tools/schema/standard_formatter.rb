# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetSchema}.
    module Schema
      # Renders tables with column names and types (no indexes or foreign keys).
      class StandardFormatter
        # @param tables [Hash{String => Hash}] table name => introspection payload
        # @param total [Integer] total number of tables in the schema
        # @param limit [Integer] max tables to display
        # @param offset [Integer] number of tables to skip
        # @return [void]
        def initialize(tables:, total:, limit:, offset:)
          @tables = tables
          @total  = total
          @limit  = limit
          @offset = offset
        end

        # @return [String] Markdown listing with column signatures
        def call
          paginated = @tables.keys.sort.drop(@offset).first(@limit)
          lines = ["# Schema (#{@total} tables, showing #{paginated.size})", '']

          paginated.each do |name|
            data = @tables[name]
            cols = (data[:columns] || []).map { |c| "#{c[:name]}:#{c[:type]}" }.join(', ')
            lines << "### #{name}"
            lines << cols
            note = partition_note(data)
            lines << note if note
            lines << ''
          end

          if @offset + @limit < @total
            lines << "_Use `detail:\"summary\"` for all #{@total} tables, " \
                     '`detail:"full"` for indexes/FKs, or `table:"name"` for one table._'
          end

          lines.join("\n")
        end

        private

        # @param data [Hash] table introspection payload
        # @return [String, nil] one-line parent/child partition note
        def partition_note(data)
          if data[:partition_of]
            note = "partition of #{data[:partition_of]}"
            note += " (#{data[:partition_bound]})" if data[:partition_bound]
            note
          elsif data[:partitioned]
            data[:partition_by] ? "partitioned by #{data[:partition_by]}" : 'partitioned'
          end
        end
      end
    end
  end
end
