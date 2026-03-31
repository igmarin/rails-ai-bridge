# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module Schema
      # Renders full table detail (columns, indexes, foreign keys) for a page of tables.
      class FullFormatter
        # @param tables [Hash] tables hash keyed by table name
        # @param total [Integer] total number of tables in the schema
        # @param limit [Integer] max tables to display
        # @param offset [Integer] number of tables to skip
        def initialize(tables:, total:, limit:, offset:)
          @tables = tables
          @total  = total
          @limit  = limit
          @offset = offset
        end

        # @return [String] Markdown full-detail listing
        def call
          paginated = @tables.keys.sort.drop(@offset).first(@limit)
          lines = [ "# Schema Full Detail (#{paginated.size} of #{@total} tables)", "" ]

          paginated.each do |name|
            lines << TableFormatter.new(name: name, data: @tables[name]).call
            lines << ""
          end

          if @offset + @limit < @total
            lines << "_Showing #{paginated.size} of #{@total}. Use `offset:#{@offset + @limit}` for more._"
          end

          lines.join("\n")
        end
      end
    end
  end
end
