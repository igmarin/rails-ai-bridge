# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool listing controllers with actions, filters, and strong params.
    class GetControllers < BaseTool
      tool_name 'rails_get_controllers'
      description 'Get controller information including actions, filters, strong params, and concerns. Optionally filter by controller name. Supports detail levels.'

      input_schema(
        properties: {
          controller: {
            type: 'string',
            description: "Optional: specific controller name (e.g. 'PostsController'). Omit for all controllers."
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'Detail level for controller listing. summary: names + action counts. standard: names + action list (default). ' \
                         'full: everything. Ignored when specific controller is given.'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param controller [String, nil] when set, return detail for that controller only
      # @param detail [String] +summary+, +standard+, or +full+ for listings
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] markdown controller summary or an error message
      def self.call(controller: nil, detail: 'standard', _server_context: nil)
        data = cached_section(:controllers)
        return text_response('Controller introspection not available. Add :controllers to introspectors.') unless data
        return text_response("Controller introspection failed: #{data[:error]}") if data[:error]

        formatter = ResponseFormatter.new(data[:controllers] || {}, controller: controller, detail: detail)
        return text_response(formatter.controller_not_found_message) if formatter.controller_not_found?

        text_response(formatter.format)
      end

      # @private
      # Formats +:controllers+ introspection for {GetControllers}.
      class ResponseFormatter
        def initialize(controllers, controller:, detail:)
          @controllers = controllers
          @controller = controller
          @detail = detail
        end

        def controller_not_found?
          @controller && !controller_info
        end

        def controller_not_found_message
          "Controller '#{@controller}' not found. Available: #{@controllers.keys.sort.join(', ')}"
        end

        def format
          if @controller
            return "Error inspecting #{controller_key}: #{controller_info[:error]}" if controller_info[:error]

            format_single_controller
          else
            format_all_controllers
          end
        end

        private

        def controller_key
          @controller_key ||= @controllers.keys.find { |k| k.downcase == @controller.downcase } || @controller
        end

        def controller_info
          @controller_info ||= @controllers[controller_key]
        end

        def format_all_controllers
          case @detail
          when 'summary' then format_summary
          when 'standard' then format_standard
          when 'full' then format_full
          else format_name_list
          end
        end

        def format_summary
          lines = ["# Controllers (#{@controllers.size})", '']
          @controllers.keys.sort.each do |name|
            info = @controllers[name]
            action_count = info[:actions]&.size || 0
            lines << "- **#{name}** — #{action_count} actions"
          end
          lines << '' << '_Use `controller:"Name"` for full detail._'
          lines.join("\n")
        end

        def format_standard
          lines = ["# Controllers (#{@controllers.size})", '']
          @controllers.keys.sort.each do |name|
            info = @controllers[name]
            actions = info[:actions]&.join(', ') || 'none'
            lines << "- **#{name}** — #{actions}"
          end
          lines << '' << '_Use `controller:"Name"` for filters and strong params, or `detail:"full"` for everything._'
          lines.join("\n")
        end

        def format_full
          lines = ["# Controllers (#{@controllers.size})", '']
          @controllers.keys.sort.each do |name|
            info = @controllers[name]
            lines << "## #{name}"
            lines << "- Actions: #{info[:actions]&.join(', ')}" if info[:actions]&.any?
            lines << "- Filters: #{info[:filters].map { |f| "#{f[:kind]} #{f[:name]}" }.join(', ')}" if info[:filters]&.any?
            lines << "- Strong params: #{info[:strong_params].join(', ')}" if info[:strong_params]&.any?
            lines << ''
          end
          lines.join("\n")
        end

        def format_name_list
          list = @controllers.keys.sort.map { |c| "- #{c}" }.join("\n")
          "# Controllers (#{@controllers.size})\n\n#{list}"
        end

        def format_single_controller
          lines = ["# #{controller_key}", '']
          lines << "**Parent:** `#{controller_info[:parent_class]}`" if controller_info[:parent_class]
          lines << '**API controller:** yes' if controller_info[:api_controller]

          if controller_info[:actions]&.any?
            lines << '' << '## Actions'
            lines << controller_info[:actions].map { |a| "- `#{a}`" }.join("\n")
          end

          if controller_info[:filters]&.any?
            lines << '' << '## Filters'
            controller_info[:filters].each do |f|
              detail = "- `#{f[:kind]}` **#{f[:name]}**"
              detail += " (only: #{f[:only].join(', ')})" if f[:only]&.any?
              lines << detail
            end
          end

          if controller_info[:strong_params]&.any?
            lines << '' << '## Strong Params'
            lines << controller_info[:strong_params].map { |p| "- `#{p}`" }.join("\n")
          end

          lines.join("\n")
        end
      end
    end
  end
end
