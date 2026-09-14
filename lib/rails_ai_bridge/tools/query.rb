# frozen_string_literal: true

require 'timeout'

module RailsAiBridge
  module Tools
    # MCP tool running a single read-only SELECT statement on the host app's
    # established ActiveRecord connection.
    #
    # Security contract (strictly read-only):
    # - one statement per call, must start with SELECT (CTEs rejected in v1)
    # - INSERT/UPDATE/DELETE/ALTER/CREATE/PRAGMA/ATTACH and locking clauses rejected
    # - hard row limit (MAX_ROWS) applied to returned rows
    # - wall-clock statement timeout
    # - values under credential-like columns redacted via Registry::MessageSanitizer
    # - runs on the app's existing connection; no new connections are opened
    class Query < BaseTool
      tool_name 'rails_query'
      description 'Run a single read-only SELECT statement against the Rails app database. ' \
                  'Only one plain SELECT is allowed (no CTEs, no mutations, no locking clauses). ' \
                  'Rows are capped and credential-like columns are redacted.'

      # Hard upper bound for returned rows regardless of client input.
      MAX_ROWS = 100

      # Wall-clock cap for statement execution.
      TIMEOUT_SECONDS = 5.0

      # Column names matching this pattern are redacted unconditionally.
      CREDENTIAL_COLUMN_PATTERN = /(?i)(password|passwd|secret|token|api_?key|auth)/

      # Placeholder written for redacted column values.
      REDACTED = '[redacted]'

      input_schema(
        properties: {
          sql: {
            type: 'string',
            description: 'A single plain SELECT statement. Semicolons, CTEs (WITH), ' \
                         'and mutating/locking clauses are rejected.'
          },
          row_limit: {
            type: 'integer',
            description: "Max rows to return (hard cap #{MAX_ROWS}). Defaults to 20 " \
                         'for standard detail and 100 for full detail.'
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'summary: columns + row count only. standard: JSON rows (default limit 20). ' \
                         'full: JSON rows (limit up to 100).'
          }
        },
        required: ['sql']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Runs the SELECT statement and returns compact JSON (or an error payload).
      #
      # @param sql [String] a single plain SELECT statement
      # @param row_limit [Integer, nil] max rows (hard-capped at MAX_ROWS)
      # @param detail [String] +summary+, +standard+, or +full+
      # @return [MCP::Tool::Response] JSON payload with columns/rows, or {"error": "..."}
      # @raise [Timeout::Error] never escapes; converted to an error response
      def self.call(sql:, row_limit: nil, detail: 'standard')
        guard_error = Guard.new(sql).error
        return error_response(guard_error) if guard_error

        execute_and_respond(sql, row_limit, detail)
      end

      # Executes the validated statement and formats the response, converting
      # execution failures into error payloads.
      #
      # @param sql [String] validated SELECT statement
      # @param row_limit [Integer, nil] requested row limit
      # @param detail [String] detail level
      # @return [MCP::Tool::Response] compact JSON payload or {"error": message}
      def self.execute_and_respond(sql, row_limit, detail)
        result = run_with_timeout(sql)
        return result if result.is_a?(MCP::Tool::Response)

        text_response(PayloadFormatter.new(result, row_limit: row_limit, detail: detail).format.to_json)
      rescue StandardError => error
        execution_failure(error)
      end

      # Runs the statement under the timeout, converting a timeout into an
      # error response.
      #
      # @param sql [String] validated SELECT statement
      # @return [ActiveRecord::Result, MCP::Tool::Response] query result or timeout error
      def self.run_with_timeout(sql)
        with_timeout { ApplicationRecord.connection.select_all(sql.to_s) }
      rescue Timeout::Error, ActiveRecord::QueryCanceled
        timeout_error
      end

      # Executes the block under the statement timeout.
      #
      # @yield the statement execution
      # @return [Object] the block's result
      # @raise [Timeout::Error] when execution exceeds TIMEOUT_SECONDS
      def self.with_timeout(&)
        connection = ApplicationRecord.connection
        if postgres_adapter?(connection)
          with_postgres_timeout(connection, &)
        else
          Timeout.timeout(TIMEOUT_SECONDS, &)
        end
      end

      # Caps the statement on PostgreSQL via SET LOCAL (Timeout.timeout cannot
      # interrupt a stuck libpq call). Other adapters keep the Ruby timeout.
      #
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @yield the statement execution
      # @return [Object] the block's result
      def self.with_postgres_timeout(connection, &)
        ms = (TIMEOUT_SECONDS * 1000).to_i
        connection.transaction(requires_new: true) do
          connection.execute("SET LOCAL statement_timeout = #{ms}")
          connection.execute('SET TRANSACTION READ ONLY')
          yield
        end
      end
      private_class_method :with_postgres_timeout

      def self.postgres_adapter?(connection)
        connection.adapter_name.match?(/\A(PostgreSQL|PostGIS)\z/i)
      end
      private_class_method :postgres_adapter?

      # Redacts every value under a credential-like column name. The column
      # name alone is enough — the value is replaced unconditionally so that
      # opaque or non-secret-looking contents (password_digest, tokens) never
      # leave the process.
      #
      # @param columns [Array<String>] result column names
      # @param rows [Array<Hash>] result rows
      # @return [Array<Hash>] rows with credential-like columns redacted
      def self.redact_columns(columns, rows)
        redacted = columns.grep(CREDENTIAL_COLUMN_PATTERN)
        return rows if redacted.empty?

        rows.map { |row| redact_row(row, redacted) }
      end

      # Replaces the credential-like columns of a single row with [redacted].
      #
      # @param row [Hash] result row keyed by column name
      # @param columns [Array<String>] credential-like column names
      # @return [Hash] row with the given columns redacted
      def self.redact_row(row, columns)
        row.merge(columns.index_with { REDACTED })
      end

      # Builds an error response following the {"error": message} contract.
      #
      # @param message [String] error message
      # @return [MCP::Tool::Response]
      def self.error_response(message)
        text_response({ error: message }.to_json)
      end

      # @return [MCP::Tool::Response] statement-timeout error payload
      def self.timeout_error
        error_response("Query timed out after #{TIMEOUT_SECONDS} seconds.")
      end

      # Logs a failed execution and returns its sanitized message.
      #
      # @param error [StandardError] raised error
      # @return [MCP::Tool::Response] sanitized error payload
      def self.execution_failure(error)
        message = error.message
        logger = Rails.logger
        logger.error(message)
        logger.error(error.backtrace.first(5).join("\n"))
        error_response(Registry::MessageSanitizer.sanitize(message))
      end
    end
  end
end
