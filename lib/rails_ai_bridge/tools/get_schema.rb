# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool returning database schema tables, columns, indexes, and foreign keys.
    class GetSchema < BaseTool
      tool_name 'rails_get_schema'
      description 'Get the database schema for the Rails app including tables, columns, indexes, and foreign keys. ' \
                  'Optionally filter by table name. Supports detail levels and pagination for large schemas.'

      input_schema(
        properties: {
          table: {
            type: 'string',
            description: 'Specific table name for full detail. Omit for overview.'
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'Detail level. summary: table names + column counts. standard: table names + column names/types (default). ' \
                         'full: everything including indexes, FKs, comments.'
          },
          limit: {
            type: 'integer',
            description: 'Max tables to return when listing. Default: 50 for summary, 15 for standard, 5 for full.'
          },
          offset: {
            type: 'integer',
            description: 'Skip this many tables for pagination. Default: 0.'
          },
          format: {
            type: 'string',
            enum: %w[json markdown],
            description: 'Output format. Default: markdown.'
          }
        }
      )

      annotations(
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      # @param table [String, nil] when set, return full detail for that table only
      # @param detail [String] +summary+, +standard+, or +full+
      # @param limit [Integer, nil] max tables (or rows) depending on formatter defaults
      # @param offset [Integer] pagination offset for table listings
      # @param format [String] +markdown+ or +json+
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] schema markdown/JSON or an error message
      def self.call(table: nil, detail: 'standard', limit: nil, offset: 0, format: 'markdown', _server_context: nil)
        schema = cached_section(:schema)
        return text_response('Schema introspection not available. Add :schema to introspectors.') unless schema
        return text_response("Schema introspection not available: #{schema[:error]}") if schema[:error]

        formatter = ResponseFormatter.new(schema, table: table, detail: detail, limit: limit, offset: offset,
                                                  format: format)
        return text_response(formatter.table_not_found_message) if formatter.table_not_found?

        text_response(formatter.format)
      end

      # @private
      # Delegates to schema formatters for table-specific or listing output.
      class ResponseFormatter
        def initialize(schema, table:, detail:, limit:, offset:, format:)
          @schema = schema
          @table = table
          @detail = detail
          @limit = limit
          @offset = offset
          @format = format
          @tables = @schema[:tables] || {}
        end

        def table_not_found?
          @table && !@tables.key?(@table)
        end

        def table_not_found_message
          "Table '#{@table}' not found. Available: #{@tables.keys.sort.join(', ')}"
        end

        def format
          if @table
            format_single_table
          elsif @format == 'json' && @detail == 'full'
            @schema.to_json
          else
            format_all_tables
          end
        end

        private

        def format_single_table
          table_data = @tables[@table]
          @format == 'json' ? table_data.to_json : Schema::TableFormatter.new(name: @table, data: table_data).call
        end

        def format_all_tables
          total = @tables.size
          offset = [@offset.to_i, 0].max

          formatter_class, default_limit = case @detail
                                           when 'summary' then [Schema::SummaryFormatter, 50]
                                           when 'full'    then [Schema::FullFormatter, 5]
                                           else [Schema::StandardFormatter, 15]
                                           end

          formatter_class.new(tables: @tables, total: total, limit: @limit || default_limit, offset: offset).call
        end
      end
    end
  end
end
