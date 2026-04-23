# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetSchema}.
    module Schema
      # Renders a compact summary of all tables: name + column/index counts.
      class SummaryFormatter
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

        # @return [String] Markdown summary listing
        def call
          paginated = @tables.keys.sort.drop(@offset).first(@limit)
          lines = ["# Schema Summary (#{@total} tables)", '']

          paginated.each do |name|
            data = @tables[name]
            col_count = data[:columns]&.size || 0
            idx_count = data[:indexes]&.size || 0
            lines << "- **#{name}** — #{col_count} columns, #{idx_count} indexes"
          end

          if @offset + @limit < @total
            lines << '' << "_Showing #{paginated.size} of #{@total}. " \
                           "Use `offset:#{@offset + @limit}` for more, or `table:\"name\"` for full detail._"
          end

          lines.join("\n")
        end
      end
    end
  end
end
