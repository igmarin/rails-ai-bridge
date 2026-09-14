# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class Query
      # Builds the compact JSON payload for a query result, honoring the
      # detail level and the hard row cap.
      class PayloadFormatter
        # Row limits by detail level (summary never returns rows).
        LIMITS_BY_DETAIL = { 'summary' => 0, 'standard' => 20, 'full' => Query::MAX_ROWS }.freeze

        # Fallback row limit for an unrecognized detail level.
        DEFAULT_ROWS = 20

        # @param result [ActiveRecord::Result] executed statement result
        # @param row_limit [Integer, nil] requested row limit
        # @param detail [String] +summary+, +standard+, or +full+
        def initialize(result, row_limit:, detail:)
          @columns = result.columns
          @rows = Query.redact_columns(@columns, result.to_a)
          @row_limit = row_limit
          @detail = detail
        end

        # Builds the payload: columns, row count, truncation flag, and rows
        # (rows omitted for summary detail).
        #
        # @return [Hash] compact payload
        def format
          total = @rows.size
          payload = { columns: @columns, row_count: total }
          return payload if @detail == 'summary'

          payload.merge(truncated: total > limit, rows: @rows.first(limit))
        end

        private

        # Effective row limit: client request clamped to 1..MAX_ROWS, or the
        # detail-level default when no (or an invalid) limit was given.
        #
        # @return [Integer]
        def limit
          requested = @row_limit.to_i
          requested = LIMITS_BY_DETAIL.fetch(@detail, DEFAULT_ROWS) if requested < 1
          requested.clamp(1, Query::MAX_ROWS)
        end
      end
    end
  end
end
