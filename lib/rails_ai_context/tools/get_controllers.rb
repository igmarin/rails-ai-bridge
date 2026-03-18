# frozen_string_literal: true

module RailsAiContext
  module Tools
    class GetControllers < BaseTool
      tool_name "rails_get_controllers"
      description "Get controller information including actions, filters, strong params, and concerns. Optionally filter by controller name."

      input_schema(
        properties: {
          controller: {
            type: "string",
            description: "Optional: specific controller name (e.g. 'PostsController'). Omit for all controllers."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(controller: nil, server_context: nil)
        data = cached_context[:controllers]
        return text_response("Controller introspection not available. Add :controllers to introspectors.") unless data
        return text_response("Controller introspection failed: #{data[:error]}") if data[:error]

        controllers = data[:controllers] || {}

        unless controller
          list = controllers.keys.sort.map { |c| "- #{c}" }.join("\n")
          return text_response("# Controllers (#{controllers.size})\n\n#{list}")
        end

        key = controllers.keys.find { |k| k.downcase == controller.downcase } || controller
        info = controllers[key]
        return text_response("Controller '#{controller}' not found. Available: #{controllers.keys.sort.join(', ')}") unless info
        return text_response("Error inspecting #{key}: #{info[:error]}") if info[:error]

        text_response(format_controller(key, info))
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
