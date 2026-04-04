# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetSchema}.
    module Schema
      # Renders a single database table as a Markdown block with columns,
      # indexes, and foreign keys.
      class TableFormatter
        # @param name [String] table name
        # @param data [Hash] slice from schema introspection (+:columns+, +:indexes+, +:foreign_keys+)
        # @return [void]
        def initialize(name:, data:)
          @name = name
          @data = data
        end

        # @return [String] Markdown representation of the table
        def call
          lines = [ "## Table: #{@name}", "" ]
          lines << "| Column | Type | Nullable | Default |"
          lines << "|--------|------|----------|---------|"

          (@data[:columns] || []).each do |col|
            lines << "| #{col[:name]} | #{col[:type]} | #{col[:null] ? 'yes' : 'no'} | #{col[:default] || '-'} |"
          end

          if @data[:indexes]&.any?
            lines << "" << "### Indexes"
            @data[:indexes].each do |idx|
              unique = idx[:unique] ? " (unique)" : ""
              lines << "- `#{idx[:name]}` on (#{Array(idx[:columns]).join(', ')})#{unique}"
            end
          end

          if @data[:foreign_keys]&.any?
            lines << "" << "### Foreign keys"
            @data[:foreign_keys].each do |fk|
              lines << "- `#{fk[:column]}` → `#{fk[:to_table]}.#{fk[:primary_key]}`"
            end
          end

          lines.join("\n")
        end
      end
    end
  end
end
