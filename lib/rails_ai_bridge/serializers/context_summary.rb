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
        routes = context[:routes]
        return [] unless routes.is_a?(Hash) && !routes[:error]

        by_controller = routes[:by_controller]
        return [] unless by_controller.is_a?(Hash) && by_controller.any?

        bounded_limit = limit.to_i.clamp(1, 20)
        by_controller
          .sort_by { |controller, controller_routes| [-Array(controller_routes).size, controller.to_s] }
          .first(bounded_limit)
          .map do |controller, controller_routes|
            count = Array(controller_routes).size
            "- #{controller}: #{count} routes — `rails_get_routes(controller:\"#{controller}\", detail:\"summary\")`"
          end
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
        return 0 unless data.is_a?(Hash)

        tier_score(data[:semantic_tier]) +
          model_complexity_score(data) +
          route_density_for_model(name, data, context) +
          recent_migration_score(data, context) +
          database_size_score(data, context)
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
        return nil if row_count.nil?

        rows = row_count.to_i
        case rows
        when 0...50_000 then 'small'
        when 50_000...1_000_000 then 'medium'
        when 1_000_000...10_000_000 then 'large'
        else 'hot'
        end
      end

      # Optional size bucket for a table from +context[:database_stats]+.
      #
      # @param context [Hash] full introspection hash
      # @param table_name [String, nil]
      # @return [String, nil]
      def database_size_bucket_for_table(context, table_name)
        return nil if table_name.to_s.empty?

        stats = context[:database_stats]
        return nil unless stats.is_a?(Hash) && !stats[:error] && !stats[:skipped]

        row = Array(stats[:tables]).find do |table_stats|
          table_stats[:table].to_s == table_name.to_s || table_stats['table'].to_s == table_name.to_s
        end
        return nil unless row

        database_size_bucket(row[:approximate_rows] || row['approximate_rows'])
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

      private

      def displayable_column?(column)
        return false unless column.is_a?(Hash)

        column_name = column[:name]
        return false unless column_name.present? && column[:type].present?

        HOUSEKEEPING_COLUMNS.exclude?(column_name) && !column_name.to_s.end_with?('_id')
      end
      module_function :displayable_column?
      private_class_method :displayable_column?

      TIER_SCORES = {
        'core_entity' => 100,
        'rich_join' => 35,
        'supporting' => 20,
        'pure_join' => 5
      }.freeze
      private_constant :TIER_SCORES

      def tier_score(tier)
        TIER_SCORES.fetch(tier.to_s, 20)
      end
      module_function :tier_score
      private_class_method :tier_score

      def route_density_for_model(name, data, context)
        by_controller = context.dig(:routes, :by_controller)
        return 0 unless by_controller.is_a?(Hash)

        route_keys_for_model(name, data).sum { |key| Array(by_controller[key]).size }
      end
      module_function :route_density_for_model
      private_class_method :route_density_for_model

      def route_keys_for_model(name, data)
        keys = []
        keys << name.to_s.delete_suffix('Controller').underscore.pluralize if name
        table_name = data[:table_name].to_s
        keys << table_name if table_name.present?
        keys.uniq
      end
      module_function :route_keys_for_model
      private_class_method :route_keys_for_model

      def recent_migration_score(data, context)
        recently_migrated?(data[:table_name], context[:migrations]) ? 5 : 0
      end
      module_function :recent_migration_score
      private_class_method :recent_migration_score

      def database_size_score(data, context)
        case database_size_bucket_for_table(context, data[:table_name])
        when 'hot' then 12
        when 'large' then 8
        when 'medium' then 3
        else 0
        end
      end
      module_function :database_size_score
      private_class_method :database_size_score

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
