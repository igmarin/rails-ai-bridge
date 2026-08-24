# frozen_string_literal: true

module RailsAiBridge
  # Shared utility for mapping approximate database row counts to safe,
  # human-oriented size bucket labels (+small+, +medium+, +large+, +hot+).
  #
  # Extracted from +Serializers::ContextSummary+ so that both the introspection
  # layer and the serializer layer can use it without introspectors depending
  # on serializers (an ArchSpec boundary violation).
  class DatabaseSize
    # @param row_count [Integer, nil]
    # @return [String, nil] safe size bucket label
    def self.bucket(row_count)
      BucketLabel.new(row_count).label
    end

    # @param context [Hash]
    # @param table_name [String, nil]
    # @return [String, nil] safe size bucket label for the table
    def self.bucket_for_table(context, table_name)
      new(context).bucket_for_table(table_name)
    end

    def initialize(context)
      @context = context
    end

    # @param row_count [Integer, nil]
    # @return [String, nil] safe size bucket label
    delegate :bucket, to: :class

    # @param table_name [String, nil]
    # @return [String, nil] safe size bucket label for the table
    def bucket_for_table(table_name)
      table_stats = row_for(table_name.to_s)
      return unless table_stats

      stats = table_stats.with_indifferent_access
      bucket(stats[:size_bucket] || stats[:approximate_rows])
    end

    private

    def row_for(table_name)
      return nil if table_name.empty? || invalid_stats?

      Array(stats[:tables]).find do |table_stats|
        table_stats[:table].to_s == table_name || table_stats['table'].to_s == table_name
      end
    end

    def invalid_stats?
      !stats.is_a?(Hash) || stats[:error] || stats[:skipped]
    end

    def stats
      @context&.fetch(:database_stats, nil)
    end

    BUCKETS = {
      0...50_000 => 'small',
      50_000...1_000_000 => 'medium',
      1_000_000...10_000_000 => 'large'
    }.freeze
    private_constant :BUCKETS

    # Value object for mapping an approximate row count to a safe label.
    class BucketLabel
      SAFE_LABELS = %w[small medium large hot].freeze
      private_constant :SAFE_LABELS

      def initialize(row_count)
        @value = row_count
      end

      # @return [String, nil] safe size bucket label
      def label
        return @value if SAFE_LABELS.include?(@value)
        return nil unless rows

        BUCKETS.find { |range, _bucket| range.cover?(rows) }&.last || 'hot'
      end

      private

      def rows
        @rows ||= @value&.to_i
      end
    end
  end
end
