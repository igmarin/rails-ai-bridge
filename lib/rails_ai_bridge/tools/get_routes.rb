# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool listing routes with optional controller filter, detail level, and pagination.
    class GetRoutes < BaseTool
      tool_name 'rails_get_routes'
      description 'Get all routes for the Rails app, optionally filtered by controller. Shows HTTP verb, path, controller#action, and route name. Supports detail levels and pagination.'

      input_schema(
        properties: {
          controller: {
            type: 'string',
            description: "Filter routes by controller name (e.g. 'users', 'api/v1/posts')."
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'Detail level. summary: route counts per controller. standard: paths and actions (default). full: everything including names and constraints.'
          },
          limit: {
            type: 'integer',
            description: 'Max routes to return. Default: depends on detail level.'
          },
          offset: {
            type: 'integer',
            description: 'Skip routes for pagination. Default: 0.'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param controller [String, nil] filter by controller path/name
      # @param detail [String] +summary+, +standard+, or +full+
      # @param limit [Integer, nil] max routes to include
      # @param offset [Integer] pagination offset
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] markdown routes output or an error message
      def self.call(controller: nil, detail: 'standard', limit: nil, offset: 0, _server_context: nil)
        routes = cached_section(:routes)
        return text_response('Route introspection not available. Add :routes to introspectors.') unless routes
        return text_response("Route introspection failed: #{routes[:error]}") if routes[:error]

        formatter = ResponseFormatter.new(routes, controller: controller, detail: detail, limit: limit, offset: offset)
        return text_response(formatter.filter_error_message) if formatter.filter_error?

        text_response(formatter.format)
      end

      # @private
      # Formats +:routes+ introspection for {GetRoutes}.
      class ResponseFormatter
        def initialize(routes, controller:, detail:, limit:, offset:)
          @routes = routes
          @controller = controller
          @detail = detail
          @limit = limit
          @offset = [offset.to_i, 0].max
          @by_controller = filter_by_controller
        end

        def filter_error?
          @controller && @by_controller.empty?
        end

        def filter_error_message
          "No routes for '#{@controller}'. Controllers: #{@routes[:by_controller].keys.sort.join(', ')}"
        end

        def format
          case @detail
          when 'summary' then format_summary
          when 'standard' then format_standard
          when 'full' then format_full
          else "Unknown detail level: #{@detail}. Use summary, standard, or full."
          end
        end

        private

        def filter_by_controller
          return @routes[:by_controller] || {} unless @controller

          (@routes[:by_controller] || {}).select { |k, _| k.downcase.include?(@controller.downcase) }
        end

        def format_summary
          lines = ["# Routes Summary (#{@routes[:total_routes]} total)", '']
          @by_controller.keys.sort.each do |ctrl|
            actions = @by_controller[ctrl]
            verbs = actions.map { |r| r[:verb] }.tally.map { |v, c| "#{c} #{v}" }.join(', ')
            lines << "- **#{ctrl}** — #{actions.size} routes (#{verbs})"
          end
          lines << '' << "API namespaces: #{@routes[:api_namespaces].join(', ')}" if @routes[:api_namespaces]&.any?
          lines << '' << '_Use `controller:"name"` to see routes for a specific controller._'
          lines.join("\n")
        end

        def format_standard
          limit = @limit || 100
          lines = ["# Routes (#{@routes[:total_routes]} total)", '']
          count = 0
          @by_controller.sort.each do |ctrl, actions|
            next if count >= @offset + limit

            ctrl_lines = []
            actions.each do |r|
              count += 1
              next if count <= @offset
              break if count > @offset + limit

              ctrl_lines << "- `#{r[:verb]}` `#{r[:path]}` → #{r[:action]}"
            end
            next unless ctrl_lines.any?

            lines << "## #{ctrl}"
            lines.concat(ctrl_lines)
            lines << ''
          end
          if @routes[:total_routes] > limit
            lines << '_Use `detail:"summary"` for overview, or `detail:"full"` for route names._'
          end
          lines.join("\n")
        end

        def format_full
          limit = @limit || 200
          lines = ["# Routes Full Detail (#{@routes[:total_routes]} total)", '']
          lines << '| Verb | Path | Controller#Action | Name |'
          lines << '|------|------|-------------------|------|'
          count = 0
          @by_controller.sort.each do |ctrl, actions|
            actions.each do |r|
              count += 1
              next if count <= @offset
              break if count > @offset + limit

              lines << "| #{r[:verb]} | `#{r[:path]}` | #{ctrl}##{r[:action]} | #{r[:name] || '-'} |"
            end
          end
          lines << '' << "## API namespaces: #{@routes[:api_namespaces].join(', ')}" if @routes[:api_namespaces]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
