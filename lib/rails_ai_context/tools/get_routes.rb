# frozen_string_literal: true

module RailsAiContext
  module Tools
    class GetRoutes < BaseTool
      tool_name "rails_get_routes"
      description "Get all routes for the Rails app, optionally filtered by controller. Shows HTTP verb, path, controller#action, and route name. Supports detail levels and pagination."

      input_schema(
        properties: {
          controller: {
            type: "string",
            description: "Filter routes by controller name (e.g. 'users', 'api/v1/posts')."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level. summary: route counts per controller. standard: paths and actions (default). full: everything including names and constraints."
          },
          limit: {
            type: "integer",
            description: "Max routes to return. Default: depends on detail level."
          },
          offset: {
            type: "integer",
            description: "Skip routes for pagination. Default: 0."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(controller: nil, detail: "standard", limit: nil, offset: 0, server_context: nil)
        routes = cached_context[:routes]
        return text_response("Route introspection not available. Add :routes to introspectors.") unless routes
        return text_response("Route introspection failed: #{routes[:error]}") if routes[:error]

        by_controller = routes[:by_controller] || {}
        offset = [ offset.to_i, 0 ].max

        # Filter by controller
        if controller
          filtered = by_controller.select { |k, _| k.downcase.include?(controller.downcase) }
          return text_response("No routes for '#{controller}'. Controllers: #{by_controller.keys.sort.join(', ')}") if filtered.empty?
          by_controller = filtered
        end

        case detail
        when "summary"
          lines = [ "# Routes Summary (#{routes[:total_routes]} total)", "" ]
          by_controller.keys.sort.each do |ctrl|
            actions = by_controller[ctrl]
            verbs = actions.map { |r| r[:verb] }.tally.map { |v, c| "#{c} #{v}" }.join(", ")
            lines << "- **#{ctrl}** — #{actions.size} routes (#{verbs})"
          end
          if routes[:api_namespaces]&.any?
            lines << "" << "API namespaces: #{routes[:api_namespaces].join(', ')}"
          end
          lines << "" << "_Use `controller:\"name\"` to see routes for a specific controller._"
          text_response(lines.join("\n"))

        when "standard"
          limit ||= 100
          lines = [ "# Routes (#{routes[:total_routes]} total)", "" ]
          count = 0
          by_controller.sort.each do |ctrl, actions|
            next if count >= offset + limit
            ctrl_lines = []
            actions.each do |r|
              count += 1
              next if count <= offset
              break if count > offset + limit
              ctrl_lines << "- `#{r[:verb]}` `#{r[:path]}` → #{r[:action]}"
            end
            if ctrl_lines.any?
              lines << "## #{ctrl}"
              lines.concat(ctrl_lines)
              lines << ""
            end
          end
          lines << "_Use `detail:\"summary\"` for overview, or `detail:\"full\"` for route names._" if routes[:total_routes] > limit
          text_response(lines.join("\n"))

        when "full"
          # Existing full table behavior
          limit ||= 200
          lines = [ "# Routes Full Detail (#{routes[:total_routes]} total)", "" ]
          lines << "| Verb | Path | Controller#Action | Name |"
          lines << "|------|------|-------------------|------|"
          count = 0
          by_controller.sort.each do |ctrl, actions|
            actions.each do |r|
              count += 1
              next if count <= offset
              break if count > offset + limit
              lines << "| #{r[:verb]} | `#{r[:path]}` | #{ctrl}##{r[:action]} | #{r[:name] || '-'} |"
            end
          end
          if routes[:api_namespaces]&.any?
            lines << "" << "## API namespaces: #{routes[:api_namespaces].join(', ')}"
          end
          text_response(lines.join("\n"))
        else
          text_response("Unknown detail level: #{detail}. Use summary, standard, or full.")
        end
      end
    end
  end
end
