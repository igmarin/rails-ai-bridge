# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetContext
      # Renders the composite markdown payload for {GetContext}.
      class Composer
        # Max association, validation, route, and filter samples in +summary+ output.
        SUMMARY_ASSOC_LIMIT = 3
        # Related-test path caps keyed by +detail+ level.
        TEST_LIMITS = { 'summary' => 5, 'standard' => 10, 'full' => 20 }.freeze

        # @param resolution [Hash] output of {Resolver#call}
        # @param snapshots [Hash{Symbol => Object}]
        # @param detail [String]
        # @param test_paths [Array<String>]
        def initialize(resolution:, snapshots:, detail:, test_paths:)
          @resolution = resolution
          @snapshots = snapshots
          @detail = %w[summary standard full].include?(detail) ? detail : 'summary'
          @test_paths = test_paths
        end

        # @return [String] markdown body
        def call
          return [@resolution[:error], *@resolution[:setup_messages]].compact.join("\n\n") if hard_error?

          lines = ["# Context: #{heading_label}", '']
          @resolution[:setup_messages].each { |message| lines << message << '' }
          append_table(lines)
          append_model(lines)
          append_routes(lines)
          append_controller(lines)
          append_tests(lines)
          lines.join("\n").strip
        end

        private

        def hard_error?
          @resolution[:error] && @resolution[:model_name].nil? && @resolution[:controller_name].nil? &&
            @resolution[:table_name].nil?
        end

        def heading_label
          @resolution[:model_name] || @resolution[:controller_name] || @resolution[:table_name] ||
            @resolution[:requested_feature] || @resolution[:requested_model] || @resolution[:requested_controller]
        end

        def append_table(lines)
          name = @resolution[:table_name]
          data = @resolution[:table_data]
          return if name.nil?

          lines << '## Table' << ''
          lines << table_body(name, data) << ''
        end

        def table_body(name, data)
          source = @resolution[:schema_source]
          case @detail
          when 'full'
            if data
              Schema::TableFormatter.new(name: name, data: data, source: source).call
            else
              "- **#{name}** #{ConfidenceTag.tag(source)}"
            end
          when 'standard'
            cols = Array(data&.[](:columns)).map { |col| "#{col[:name]}:#{col[:type]}" }.join(', ')
            "- **#{ConfidenceTag.tagged(name, source)}** — #{cols.presence || 'columns unknown'}"
          else
            col_count = data&.[](:columns)&.size || 0
            idx_count = data&.[](:indexes)&.size || 0
            "- **#{name}** #{ConfidenceTag.tag(source)} — #{col_count} columns, #{idx_count} indexes"
          end
        end

        def append_model(lines)
          name = @resolution[:model_name]
          data = @resolution[:model_data]
          return if name.nil?

          lines << '## Model' << ''
          if data.nil?
            lines << "_Model '#{name}' has no introspection payload._" << ''
            return
          end
          if data[:error]
            lines << "Error inspecting #{name}: #{data[:error]}" << ''
            return
          end

          lines << model_body(name, data) << ''
        end

        def model_body(name, data)
          case @detail
          when 'full'
            ModelDetails::SingleModelFormatter.new(name: name, data: data).call
          when 'standard'
            standard_model(name, data)
          else
            summary_model(name, data)
          end
        end

        def summary_model(name, data)
          assoc = Array(data[:associations])
          validations = Array(data[:validations])
          tier = data[:semantic_tier].present? ? ", tier: `#{data[:semantic_tier]}`" : nil
          lines = ["- **#{name}** — #{assoc.size} associations, #{validations.size} validations#{tier}"]
          assoc.first(SUMMARY_ASSOC_LIMIT).each do |entry|
            lines << ConfidenceTag.tagged("- `#{entry[:type]}` **#{entry[:name]}**", entry[:source] || :reflection)
          end
          validations.first(SUMMARY_ASSOC_LIMIT).each do |entry|
            attrs = Array(entry[:attributes]).join(', ')
            lines << "- `#{entry[:kind]}` on #{attrs}"
          end
          lines.join("\n")
        end

        def standard_model(name, data)
          lines = ["# #{name}"]
          lines << "**Table:** `#{data[:table_name]}`" if data[:table_name]
          if data[:semantic_tier].present?
            lines << "**Semantic tier:** `#{data[:semantic_tier]}`"
            lines << "**Tier reason:** #{data[:semantic_tier_reason]}" if data[:semantic_tier_reason].present?
          end
          if Array(data[:associations]).any?
            lines << '' << '## Associations'
            data[:associations].each do |entry|
              lines << ConfidenceTag.tagged("- `#{entry[:type]}` **#{entry[:name]}**", entry[:source] || :reflection)
            end
          end
          if Array(data[:validations]).any?
            lines << '' << '## Validations'
            data[:validations].each do |entry|
              attrs = Array(entry[:attributes]).join(', ')
              lines << "- `#{entry[:kind]}` on #{attrs}"
            end
          end
          lines.join("\n")
        end

        def append_routes(lines)
          routes = @resolution[:routes] || {}
          return if routes.empty?

          lines << '## Routes' << ''
          case @detail
          when 'summary'
            routes.keys.sort.each do |ctrl|
              sample = routes[ctrl].first(SUMMARY_ASSOC_LIMIT).map { |route| "`#{route[:path]}`" }.join(', ')
              lines << "- **#{ctrl}** — #{routes[ctrl].size} routes (#{sample})"
            end
          else
            routes.sort.each do |ctrl, actions|
              lines << "### #{ctrl}"
              actions.each do |route|
                extra = @detail == 'full' && route[:name] ? " (#{route[:name]})" : ''
                lines << "- `#{route[:verb]}` `#{route[:path]}` → #{route[:action]}#{extra}"
              end
              lines << ''
            end
          end
          lines << ''
        end

        def append_controller(lines)
          name = @resolution[:controller_name]
          data = @resolution[:controller_data]
          return if name.nil?

          lines << '## Controller' << ''
          if data.nil? || data[:error]
            lines << (data&.[](:error) ? "Error inspecting #{name}: #{data[:error]}" : "_No payload for #{name}._")
            lines << ''
            return
          end

          lines << controller_body(name, data) << ''
        end

        def controller_body(name, data)
          actions = Array(data[:actions])
          filters = Array(data[:filters])
          case @detail
          when 'summary'
            filter_names = filters.first(SUMMARY_ASSOC_LIMIT).pluck(:name).compact
            extra = filter_names.any? ? "; filters: #{filter_names.join(', ')}" : ''
            "- **#{name}** — #{actions.join(', ').presence || 'no actions'}#{extra}"
          when 'full'
            GetControllers::ResponseFormatter.new({ name => data }, controller: name, detail: 'full').format
          else
            parts = ["- **#{name}** — #{actions.join(', ').presence || 'no actions'}"]
            parts << filters.map { |filter| "- `#{filter[:kind]}` **#{filter[:name]}**" }.join("\n") if filters.any?
            parts.join("\n")
          end
        end

        def append_tests(lines)
          limit = TEST_LIMITS.fetch(@detail, 5)
          paths = @test_paths.first(limit)
          return if paths.empty?

          lines << '## Related tests' << ''
          paths.each { |path| lines << "- `#{path}`" }
          lines << ''
        end
      end
    end
  end
end
