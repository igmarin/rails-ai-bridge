# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Shared stack metrics so compact outputs stay consistent with split rule files
    # (e.g. +# Controllers (N)+ uses {ControllerIntrospector}, not +routes[:by_controller]+ alone).
    module ContextSummary
      # Column names excluded from compact model output — primary key, timestamps, and
      # foreign keys (matched via +_id+ suffix separately).
      HOUSEKEEPING_COLUMNS = %w[id created_at updated_at].freeze

      module_function

      # @param context [Hash] full introspection hash
      # @return [Integer, nil] number of Ruby controller classes under +app/controllers+
      def introspected_controller_count(context)
        ctrl = context[:controllers]
        return nil unless ctrl.is_a?(Hash) && !ctrl[:error]

        count = (ctrl[:controllers] || {}).size
        count.positive? ? count : nil
      end

      # @param context [Hash]
      # @return [Integer, nil] distinct controller names referenced in the route set
      def route_target_controller_count(context)
        routes = context[:routes]
        return nil unless routes.is_a?(Hash) && !routes[:error]

        count = (routes[:by_controller] || {}).keys.size
        count.positive? ? count : nil
      end

      # One stack bullet for routes + controller inventory, aligned with +rails-controllers+ split files.
      #
      # @param context [Hash]
      # @return [String, nil] markdown line starting with "- Routes:" or +nil+ if no routes data
      def routes_stack_line(context)
        routes = context[:routes]
        return nil unless routes.is_a?(Hash) && !routes[:error]

        total = routes[:total_routes]
        ic = introspected_controller_count(context)
        rt = route_target_controller_count(context)

        if ic
          suffix =
            if rt && rt != ic
              " (#{rt} names in routing — can exceed class count when routes reference engines or non-file controllers)"
            else
              ''
            end
          "- Routes: #{total} total — #{ic} controller classes#{suffix}"
        elsif rt
          "- Routes: #{total} total — #{rt} route targets (controller inventory unavailable)"
        else
          "- Routes: #{total} total"
        end
      end

      # Bounded route focus lines for passive context. Shows busiest endpoint
      # areas without dumping the full route table.
      #
      # @param context [Hash] full introspection hash
      # @param limit [Integer] max controllers to render
      # @return [Array<String>] markdown lines without heading
      def route_focus_lines(context, limit: 5)
        RouteFocus.new(context, limit).lines
      end

      # Complexity score for a single model's introspection data.
      # Used by compact serializers to surface the most architecturally significant
      # models (high association/validation/callback/scope counts) first.
      #
      # @param data [Hash] single-model entry from +context[:models]+
      # @return [Integer] non-negative score; higher = more complex
      def model_complexity_score(data)
        Array(data[:associations]).size +
          Array(data[:validations]).size +
          Array(data[:callbacks]).size +
          Array(data[:scopes]).size
      end

      # Task-relevance score for passive context ordering.
      #
      # @param data [Hash] single-model entry from +context[:models]+
      # @param name [String, nil] model class name
      # @param context [Hash] full introspection hash
      # @return [Integer] non-negative score; higher = more relevant
      def model_relevance_score(data, name: nil, context: {})
        ModelRelevance.new(data: data, name: name, context: context).score
      end

      # Valid model entries sorted by task relevance, then model name for stable
      # deterministic output when scores tie.
      #
      # @param models [Hash] model payloads keyed by model name
      # @param context [Hash] full introspection hash
      # @return [Array<Array(String, Hash)>]
      def models_by_relevance(models, context: {})
        return [] unless models.is_a?(Hash)

        models.select { |_name, data| data.is_a?(Hash) && !data[:error] }
              .sort_by { |name, data| [-model_relevance_score(data, name: name, context: context), name.to_s] }
      end

      # Valid model names grouped by semantic tier while preserving relevance ordering.
      #
      # @param models [Hash] model payloads keyed by model name
      # @param context [Hash] full introspection hash
      # @return [Hash{String => Array<String>}]
      def models_grouped_by_semantic_tier(models, context: {})
        models_by_relevance(models, context: context).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(name, data), groups|
          groups[semantic_tier_for(data)] << name
        end
      end

      # @param data [Hash, Object] single-model entry
      # @return [String] semantic tier with a stable fallback
      def semantic_tier_for(data)
        (data.is_a?(Hash) && data[:semantic_tier].presence) || 'supporting'
      end

      # Returns the appropriate test command string for this app's test framework.
      # Reads +context[:tests][:framework]+ (value returned by the tests introspector:
      # "rspec" or "minitest"). Falls back to +"bundle exec rspec"+ when the key is
      # absent, nil, or contains an unrecognised value.
      #
      # @param context [Hash] full introspection hash
      # @return [String] copy-pastable test command
      def test_command(context)
        framework = context.dig(:tests, :framework).to_s.strip.downcase
        framework == 'minitest' ? 'bin/rails test' : 'bundle exec rspec'
      end

      # Top non-housekeeping columns for a model's table.
      # Excludes primary key (+id+), timestamps (+created_at+, +updated_at+), and
      # foreign key columns (names ending in +_id+). Returns at most 3 columns.
      #
      # @param table_data [Hash, nil] entry from +context[:schema][:tables][table_name]+;
      #   must have a +:columns+ key with an array of +{ name:, type: }+ hashes.
      # @return [Array<Hash>] up to 3 column hashes with +:name+ and +:type+ keys
      def top_columns(table_data)
        return [] unless table_data.is_a?(Hash)

        columns = Array(table_data[:columns])

        columns
          .select { |column| displayable_column?(column) }
          .first(3)
          .map { |column| { name: column[:name], type: column[:type] } }
      end

      # Returns true when any migration within the last 30 days references +table_name+.
      # Migration recency is derived from the YYYYMMDDHHMMSS timestamp prefix in
      # +:version+. The table match is based on common Rails migration filename
      # forms such as +create_users+ and +add_email_to_users+.
      #
      # @param table_name [String, nil] snake_case table name (e.g. +"users"+)
      # @param migrations [Hash, nil] +context[:migrations]+ hash; must have a +:recent+ key
      # @return [Boolean]
      def recently_migrated?(table_name, migrations)
        return false unless table_name && migrations.is_a?(Hash)

        cutoff = Time.zone.today - 30
        Array(migrations[:recent]).any? do |m|
          version = m[:version].to_s
          next false unless version.length >= 8

          migration_date = Date.strptime(version[0..7], '%Y%m%d')
          migration_date >= cutoff && migration_filename_matches_table?(m[:filename], table_name)
        rescue ArgumentError
          false
        end
      end

      # Human-oriented approximate table size bucket for optional database stats.
      #
      # @param row_count [Integer, nil] approximate rows
      # @return [String, nil] +small+, +medium+, +large+, +hot+, or nil
      def database_size_bucket(row_count)
        DatabaseSize.bucket(row_count)
      end

      # Optional size bucket for a table from +context[:database_stats]+.
      #
      # @param context [Hash] full introspection hash
      # @param table_name [String, nil]
      # @return [String, nil]
      def database_size_bucket_for_table(context, table_name)
        DatabaseSize.bucket_for_table(context, table_name)
      end

      # Short, copy-pastable baseline for compact serializers (performance, drift, MCP exposure).
      #
      # @return [Array<String>] markdown lines (including heading)
      def compact_performance_security_section
        [
          '## Performance & security (baseline)',
          '- Large or hot tables: mind indexes and N+1s; use `includes`, batching, and bounded queries — validate with `rails_get_schema` and real load patterns.',
          '- Treat generated context as **snapshots** that can drift; prefer `rails_*` MCP tools for authoritative structure when in doubt.',
          '- Merge team-specific rules (performance, auth, compliance) into these files or companion rules — generated output is generic.',
          '- MCP is read-only but exposes app structure; avoid exposing the HTTP transport on untrusted networks.'
        ]
      end

      # Renders bounded route focus lines for compact passive context.
      class RouteFocus
        def initialize(context, limit)
          @routes = context[:routes]
          @limit = limit
        end

        # @return [Array<String>] bounded Markdown route-focus lines
        def lines
          return [] if controller_routes.empty?

          sorted_routes.first(bounded_limit).map { |controller, routes| route_line(controller, routes) }
        end

        private

        def controller_routes
          return {} unless @routes.is_a?(Hash) && !@routes[:error]

          by_controller = @routes[:by_controller]
          by_controller.is_a?(Hash) ? by_controller : {}
        end

        def sorted_routes
          controller_routes.sort_by { |controller, routes| [-route_count(routes), controller.to_s] }
        end

        def route_count(routes)
          Array(routes).size
        end

        def bounded_limit
          @limit.to_i.clamp(1, 20)
        end

        def route_line(controller, routes)
          "- #{controller}: #{route_count(routes)} routes — `rails_get_routes(controller:\"#{controller}\", detail:\"summary\")`"
        end
      end

      # Calculates model ordering relevance for compact context summaries.
      class ModelRelevance
        # Semantic-tier weights used before structural complexity and activity signals.
        TIER_SCORES = {
          'core_entity' => 100,
          'rich_join' => 35,
          'supporting' => 20,
          'pure_join' => 5
        }.freeze

        def initialize(data:, name:, context:)
          @data = data
          @name = name
          @context = context
        end

        # @return [Integer] model task-relevance score
        def score
          return 0 unless @data.is_a?(Hash)

          tier_score +
            ContextSummary.model_complexity_score(@data) +
            route_density +
            recent_migration_score +
            database_size_score
        end

        private

        def tier_score
          TIER_SCORES.fetch(@data[:semantic_tier].to_s, 20)
        end

        def route_density
          by_controller = @context.dig(:routes, :by_controller)
          return 0 unless by_controller.is_a?(Hash)

          route_keys.sum { |key| Array(by_controller[key]).size }
        end

        def route_keys
          [controller_route_key, table_name].compact_blank.uniq
        end

        def controller_route_key
          @name.to_s.delete_suffix('Controller').underscore.pluralize if @name
        end

        def table_name
          @data[:table_name].to_s
        end

        def recent_migration_score
          ContextSummary.recently_migrated?(table_name, @context[:migrations]) ? 5 : 0
        end

        def database_size_score
          case DatabaseSize.bucket_for_table(@context, table_name)
          when 'hot' then 12
          when 'large' then 8
          when 'medium' then 3
          else 0
          end
        end
      end

      # Looks up optional database row-count buckets without exposing raw counts.
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
        def bucket(row_count)
          self.class.bucket(row_count)
        end

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
      private_constant :RouteFocus, :ModelRelevance, :DatabaseSize

      private

      def displayable_column?(column)
        return false unless column.is_a?(Hash)

        column_name = column[:name]
        return false unless column_name.present? && column[:type].present?

        HOUSEKEEPING_COLUMNS.exclude?(column_name) && !column_name.to_s.end_with?('_id')
      end
      module_function :displayable_column?
      private_class_method :displayable_column?

      def migration_filename_matches_table?(filename, table_name)
        stem = File.basename(filename.to_s, '.rb').sub(/\A\d+_/, '')
        escaped_table_name = Regexp.escape(table_name.to_s)

        [
          /\Acreate_#{escaped_table_name}\z/,
          /\Achange_#{escaped_table_name}\z/,
          /\Aupdate_#{escaped_table_name}\z/,
          /\Aadd_.+_to_#{escaped_table_name}\z/,
          /\Aremove_.+_from_#{escaped_table_name}\z/,
          /\Arename_.+_(?:to|from)_#{escaped_table_name}\z/
        ].any? { |pattern| stem.match?(pattern) }
      end
      module_function :migration_filename_matches_table?
      private_class_method :migration_filename_matches_table?
    end
  end
end
