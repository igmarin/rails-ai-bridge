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

        if table
          table_data = tables[table]
          return text_response("Table '#{table}' not found. Available: #{tables.keys.sort.join(', ')}") unless table_data
          output = format == "json" ? table_data.to_json : Schema::TableFormatter.new(name: table, data: table_data).call
          return text_response(output)
        end

        return text_response(schema.to_json) if format == "json" && detail == "full"

        total  = tables.size
        offset = [ offset.to_i, 0 ].max

        formatter_class, default_limit = case detail
        when "summary" then [ Schema::SummaryFormatter, 50 ]
        when "full"    then [ Schema::FullFormatter,     5 ]
        else                [ Schema::StandardFormatter, 15 ]
        end

        text_response(formatter_class.new(tables: tables, total: total, limit: limit || default_limit, offset: offset).call)
      end
    end
  end
end
