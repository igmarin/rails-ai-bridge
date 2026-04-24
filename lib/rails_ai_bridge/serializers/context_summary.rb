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
          .reject { |c| HOUSEKEEPING_COLUMNS.include?(c[:name]) || c[:name].to_s.end_with?('_id') }
          .first(3)
          .map { |c| { name: c[:name], type: c[:type] } }
      end

      # Returns true when any migration within the last 30 days references +table_name+.
      # Migration recency is derived from the YYYYMMDDHHMMSS timestamp prefix in
      # +:version+. The table match is a substring search on +:filename+.
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
          migration_date >= cutoff && m[:filename].to_s.include?(table_name)
        rescue ArgumentError
          false
        end
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
    end
  end
end
