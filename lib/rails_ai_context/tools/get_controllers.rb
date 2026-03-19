# frozen_string_literal: true

module RailsAiContext
  module Tools
    class GetControllers < BaseTool
      tool_name "rails_get_controllers"
      description "Get controller information including actions, filters, strong params, and concerns. Optionally filter by controller name. Supports detail levels."

      input_schema(
        properties: {
          controller: {
            type: "string",
            description: "Optional: specific controller name (e.g. 'PostsController'). Omit for all controllers."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level for controller listing. summary: names + action counts. standard: names + action list (default). full: everything. Ignored when specific controller is given."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(controller: nil, detail: "standard", server_context: nil)
        data = cached_context[:controllers]
        return text_response("Controller introspection not available. Add :controllers to introspectors.") unless data
        return text_response("Controller introspection failed: #{data[:error]}") if data[:error]

        controllers = data[:controllers] || {}

        # Specific controller — always full detail
        if controller
          key = controllers.keys.find { |k| k.downcase == controller.downcase } || controller
          info = controllers[key]
          return text_response("Controller '#{controller}' not found. Available: #{controllers.keys.sort.join(', ')}") unless info
          return text_response("Error inspecting #{key}: #{info[:error]}") if info[:error]
          return text_response(format_controller(key, info))
        end

        # Listing mode
        case detail
        when "summary"
          lines = [ "# Controllers (#{controllers.size})", "" ]
          controllers.keys.sort.each do |name|
            info = controllers[name]
            action_count = info[:actions]&.size || 0
            lines << "- **#{name}** — #{action_count} actions"
          end
          lines << "" << "_Use `controller:\"Name\"` for full detail._"
          text_response(lines.join("\n"))

        when "standard"
          lines = [ "# Controllers (#{controllers.size})", "" ]
          controllers.keys.sort.each do |name|
            info = controllers[name]
            actions = info[:actions]&.join(", ") || "none"
            lines << "- **#{name}** — #{actions}"
          end
          lines << "" << "_Use `controller:\"Name\"` for filters and strong params, or `detail:\"full\"` for everything._"
          text_response(lines.join("\n"))

        when "full"
          lines = [ "# Controllers (#{controllers.size})", "" ]
          controllers.keys.sort.each do |name|
            info = controllers[name]
            lines << "## #{name}"
            lines << "- Actions: #{info[:actions]&.join(', ')}" if info[:actions]&.any?
            if info[:filters]&.any?
              lines << "- Filters: #{info[:filters].map { |f| "#{f[:kind]} #{f[:name]}" }.join(', ')}"
            end
            lines << "- Strong params: #{info[:strong_params].join(', ')}" if info[:strong_params]&.any?
            lines << ""
          end
          text_response(lines.join("\n"))

        else
          list = controllers.keys.sort.map { |c| "- #{c}" }.join("\n")
          text_response("# Controllers (#{controllers.size})\n\n#{list}")
        end
      end

      private_class_method def self.format_controller(name, info)
        lines = [ "# #{name}", "" ]
        lines << "**Parent:** `#{info[:parent_class]}`" if info[:parent_class]
        lines << "**API controller:** yes" if info[:api_controller]

        if info[:actions]&.any?
          lines << "" << "## Actions"
          lines << info[:actions].map { |a| "- `#{a}`" }.join("\n")
        end

        if info[:filters]&.any?
          lines << "" << "## Filters"
          info[:filters].each do |f|
            detail = "- `#{f[:kind]}` **#{f[:name]}**"
            detail += " (only: #{f[:only].join(', ')})" if f[:only]&.any?
            lines << detail
          end
        end

        if info[:strong_params]&.any?
          lines << "" << "## Strong Params"
          lines << info[:strong_params].map { |p| "- `#{p}`" }.join("\n")
        end

        lines.join("\n")
      end
    end
  end
end
