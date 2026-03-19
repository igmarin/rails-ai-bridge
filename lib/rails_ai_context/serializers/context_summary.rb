# frozen_string_literal: true

module RailsAiContext
  module Serializers
    # Shared stack metrics so compact outputs stay consistent with split rule files
    # (e.g. +# Controllers (N)+ uses {ControllerIntrospector}, not +routes[:by_controller]+ alone).
    module ContextSummary
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
              ""
            end
          "- Routes: #{total} total — #{ic} controller classes#{suffix}"
        elsif rt
          "- Routes: #{total} total — #{rt} route targets (controller inventory unavailable)"
        else
          "- Routes: #{total} total"
        end
      end

      # Short, copy-pastable baseline for compact serializers (performance, drift, MCP exposure).
      #
      # @return [Array<String>] markdown lines (including heading)
      def compact_performance_security_section
        [
          "## Performance & security (baseline)",
          "- Large or hot tables: mind indexes and N+1s; use `includes`, batching, and bounded queries — validate with `rails_get_schema` and real load patterns.",
          "- Treat generated context as **snapshots** that can drift; prefer `rails_*` MCP tools for authoritative structure when in doubt.",
          "- Merge team-specific rules (performance, auth, compliance) into these files or companion rules — generated output is generic.",
          "- MCP is read-only but exposes app structure; avoid exposing the HTTP transport on untrusted networks."
        ]
      end
    end
  end
end
