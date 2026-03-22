# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetSchema < BaseTool
      tool_name "rails_get_schema"
      description "Get the database schema for the Rails app including tables, columns, indexes, and foreign keys. Optionally filter by table name. Supports detail levels and pagination for large schemas."

      input_schema(
        properties: {
          table: {
            type: "string",
            description: "Specific table name for full detail. Omit for overview."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level. summary: table names + column counts. standard: table names + column names/types (default). full: everything including indexes, FKs, comments."
          },
          limit: {
            type: "integer",
            description: "Max tables to return when listing. Default: 50 for summary, 15 for standard, 5 for full."
          },
          offset: {
            type: "integer",
            description: "Skip this many tables for pagination. Default: 0."
          },
          format: {
            type: "string",
            enum: %w[json markdown],
            description: "Output format. Default: markdown."
          }
        }
      )

      annotations(
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      def self.call(table: nil, detail: "standard", limit: nil, offset: 0, format: "markdown", server_context: nil)
        schema = cached_section(:schema)
        return text_response("Schema introspection not available. Add :schema to introspectors.") unless schema
        return text_response("Schema introspection not available: #{schema[:error]}") if schema[:error]

        tables = schema[:tables] || {}

        # Single table — always full detail (existing behavior)
        if table
          table_data = tables[table]
          return text_response("Table '#{table}' not found. Available: #{tables.keys.sort.join(', ')}") unless table_data
          output = format == "json" ? table_data.to_json : format_table_markdown(table, table_data)
          return text_response(output)
        end

        # Return full JSON if requested (existing behavior)
        return text_response(schema.to_json) if format == "json" && detail == "full"

        total = tables.size
        offset = [ offset.to_i, 0 ].max

        case detail
        when "summary"
          limit ||= 50
          paginated = tables.keys.sort.drop(offset).first(limit)
          lines = [ "# Schema Summary (#{total} tables)", "" ]
          paginated.each do |name|
            data = tables[name]
            col_count = data[:columns]&.size || 0
            idx_count = data[:indexes]&.size || 0
            lines << "- **#{name}** — #{col_count} columns, #{idx_count} indexes"
          end
          lines << "" << "_Showing #{paginated.size} of #{total}. Use `offset:#{offset + limit}` for more, or `table:\"name\"` for full detail._" if offset + limit < total
          text_response(lines.join("\n"))

        when "standard"
          limit ||= 15
          paginated = tables.keys.sort.drop(offset).first(limit)
          lines = [ "# Schema (#{total} tables, showing #{paginated.size})", "" ]
          paginated.each do |name|
            data = tables[name]
            cols = (data[:columns] || []).map { |c| "#{c[:name]}:#{c[:type]}" }.join(", ")
            lines << "### #{name}"
            lines << cols
            lines << ""
          end
          lines << "_Use `detail:\"summary\"` for all #{total} tables, `detail:\"full\"` for indexes/FKs, or `table:\"name\"` for one table._" if total > limit
          text_response(lines.join("\n"))

        when "full"
          # Existing behavior — but now with optional pagination
          limit ||= 5
          paginated = tables.keys.sort.drop(offset).first(limit)
          lines = [ "# Schema Full Detail (#{paginated.size} of #{total} tables)", "" ]
          paginated.each do |name|
            lines << format_table_markdown(name, tables[name])
            lines << ""
          end
          lines << "_Showing #{paginated.size} of #{total}. Use `offset:#{offset + limit}` for more._" if offset + limit < total
          text_response(lines.join("\n"))
        else
          # Fallback to full dump (backward compat)
          text_response(format_schema_markdown(schema))
        end
      end

      private_class_method def self.format_table_markdown(name, data)
        lines = [ "## Table: #{name}", "" ]
        lines << "| Column | Type | Nullable | Default |"
        lines << "|--------|------|----------|---------|"

        (data[:columns] || []).each do |col|
          lines << "| #{col[:name]} | #{col[:type]} | #{col[:null] ? 'yes' : 'no'} | #{col[:default] || '-'} |"
        end

        if data[:indexes]&.any?
          lines << "" << "### Indexes"
          data[:indexes].each do |idx|
            unique = idx[:unique] ? " (unique)" : ""
            lines << "- `#{idx[:name]}` on (#{Array(idx[:columns]).join(', ')})#{unique}"
          end
        end

        if data[:foreign_keys]&.any?
          lines << "" << "### Foreign keys"
          data[:foreign_keys].each do |fk|
            lines << "- `#{fk[:column]}` → `#{fk[:to_table]}.#{fk[:primary_key]}`"
          end
        end

        lines.join("\n")
      end

      private_class_method def self.format_schema_markdown(schema)
        lines = [
          "# Database Schema",
          "",
          "- Adapter: #{schema[:adapter]}",
          "- Tables: #{schema[:total_tables]}",
          ""
        ]

        (schema[:tables] || {}).each do |name, data|
          cols = (data[:columns] || []).map { |c| "#{c[:name]}:#{c[:type]}" }.join(", ")
          lines << "### #{name}"
          lines << cols
          lines << ""
        end

        lines.join("\n")
      end
    end
  end
end
