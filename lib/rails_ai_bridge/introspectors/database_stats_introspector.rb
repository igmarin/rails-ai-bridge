# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Collects approximate row counts from PostgreSQL's pg_stat_user_tables.
    # Only activates for PostgreSQL adapter; returns { skipped: true } otherwise.
    class DatabaseStatsIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        return { skipped: true, reason: 'ActiveRecord not available' } unless defined?(ActiveRecord::Base)

        adapter = ActiveRecord::Base.connection.adapter_name.downcase
        return { skipped: true, reason: "Only available for PostgreSQL (current: #{adapter})" } unless adapter.include?('postgresql')

        rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
          SELECT relname AS table_name,
                 n_live_tup AS approximate_row_count
          FROM pg_stat_user_tables
          ORDER BY n_live_tup DESC
        SQL

        tables = rows.map do |row|
          { table: row['table_name'], approximate_rows: row['approximate_row_count'].to_i }
        end

        { adapter: 'postgresql', tables: tables, total_tables: tables.size }
      rescue StandardError => error
        { error: error.message }
      end
    end
  end
end
