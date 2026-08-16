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
        # @param source [Symbol, String, nil] +:live+ (verified) or +:static+ (inferred)
        # @return [void]
        def initialize(name:, data:, source: nil)
          @name = name
          @data = data
          @source = source
        end

        # @return [String] Markdown representation of the table
        def call
          lines = ["## Table: #{ConfidenceTag.tagged(@name, @source)}", '']
          lines << '| Column | Type | Nullable | Default |'
          lines << '|--------|------|----------|---------|'

          (@data[:columns] || []).each do |col|
            lines << "| #{col[:name]} | #{col[:type]} | #{col[:null] ? 'yes' : 'no'} | #{col[:default] || '-'} |"
          end

          if @data[:indexes]&.any?
            lines << '' << '### Indexes'
            @data[:indexes].each do |idx|
              unique = idx[:unique] ? ' (unique)' : ''
              lines << "- `#{idx[:name]}` on (#{Array(idx[:columns]).join(', ')})#{unique}"
            end
          end

          if @data[:foreign_keys]&.any?
            lines << '' << '### Foreign keys'
            @data[:foreign_keys].each do |fk|
              lines << "- `#{fk[:column]}` → `#{fk[:to_table]}.#{fk[:primary_key]}`"
            end
          end

          lines.join("\n")
        end

        private

        # @return [String, nil] italic partition relationship line for full detail
        def partition_heading
          if @data[:partition_of]
            note = "_Partition of `#{@data[:partition_of]}`"
            note += " — #{@data[:partition_bound]}" if @data[:partition_bound]
            "#{note}_"
          elsif @data[:partitioned]
            @data[:partition_by] ? "_Partitioned by #{@data[:partition_by]}_" : '_Partitioned_'
          end
        end
      end
    end
  end
end
