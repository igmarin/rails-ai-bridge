# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Exposes Stimulus controller metadata through MCP so assistants can inspect
    # Hotwire wiring without reading every JavaScript controller file.
    class GetStimulus < BaseTool
      tool_name "rails_get_stimulus"
      description "Get Stimulus controller information including targets, values, actions, outlets, and classes. Optionally filter by controller name."

      input_schema(
        properties: {
          controller: {
            type: "string",
            description: "Optional Stimulus controller name (for example: 'clipboard' or 'admin--filters')."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level for controller listings. summary: counts. standard: names plus targets/actions. full: everything."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Returns summarized or controller-specific Stimulus metadata.
      #
      # @param controller [String, nil] specific Stimulus controller name
      # @param detail [String] one of `summary`, `standard`, or `full`
      # @param server_context [Object, nil] MCP server context
      # @return [MCP::Tool::Response] formatted Stimulus controller information
      def self.call(controller: nil, detail: "standard", server_context: nil)
        data = cached_section(:stimulus)
        return text_response("Stimulus introspection not available. Add :stimulus to introspectors.") unless data
        return text_response("Stimulus introspection failed: #{data[:error]}") if data[:error]

        formatter = ResponseFormatter.new(Array(data[:controllers]), controller: controller, detail: detail)
        return text_response(formatter.controller_not_found_message) if formatter.controller_not_found?

        text_response(formatter.format)
      end

      # @private
      # Formats Stimulus controller metadata for {GetStimulus}.
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
          "Stimulus controller '#{@controller}' not found."
        end

        def format
          if @controller
            format_single_controller
          else
            format_all_controllers
          end
        end

        private

        def controller_info
          @controller_info ||= @controllers.find { |entry| entry[:name].to_s.casecmp?(@controller) }
        end

        def format_all_controllers
          case @detail
          when "summary" then format_summary
          when "full"    then format_full
          else                format_standard
          end
        end

        def format_single_controller
          format_controller(controller_info)
        end

        def format_summary
          lines = [ "# Stimulus Controllers (#{@controllers.size})", "" ]
          @controllers.sort_by { |entry| entry[:name].to_s }.each do |entry|
            lines << "- **#{entry[:name]}** — #{Array(entry[:targets]).size} targets, #{Array(entry[:actions]).size} actions"
          end
          lines.join("\n")
        end

        def format_standard
          lines = [ "# Stimulus Controllers (#{@controllers.size})", "" ]
          @controllers.sort_by { |entry| entry[:name].to_s }.each do |entry|
            lines << "## #{entry[:name]}"
            lines << "- Targets: #{Array(entry[:targets]).join(', ')}" if Array(entry[:targets]).any?
            lines << "- Actions: #{Array(entry[:actions]).join(', ')}" if Array(entry[:actions]).any?
            lines << "- Values: #{entry[:values].keys.join(', ')}" if entry[:values].is_a?(Hash) && entry[:values].any?
            lines << ""
          end
          lines.join("\n")
        end

        def format_full
          lines = [ "# Stimulus Controllers (#{@controllers.size})", "" ]
          @controllers.sort_by { |entry| entry[:name].to_s }.each do |entry|
            lines << "## #{entry[:name]}"
            lines << "- File: #{entry[:file]}" if entry[:file]
            lines << "- Targets: #{Array(entry[:targets]).join(', ')}" if Array(entry[:targets]).any?
            if entry[:values].is_a?(Hash) && entry[:values].any?
              lines << "- Values: #{entry[:values].map { |name, value_type| "#{name}: #{value_type}" }.join(', ')}"
            end
            lines << "- Actions: #{Array(entry[:actions]).join(', ')}" if Array(entry[:actions]).any?
            lines << "- Outlets: #{Array(entry[:outlets]).join(', ')}" if Array(entry[:outlets]).any?
            lines << "- Classes: #{Array(entry[:classes]).join(', ')}" if Array(entry[:classes]).any?
            lines << ""
          end
          lines.join("\n")
        end

        def format_controller(entry)
          lines = [ "# #{entry[:name]}", "" ]
          lines << "- File: #{entry[:file]}" if entry[:file]

          if Array(entry[:targets]).any?
            lines << "" << "## Targets"
            Array(entry[:targets]).each { |target| lines << "- `#{target}`" }
          end

          if entry[:values].is_a?(Hash) && entry[:values].any?
            lines << "" << "## Values"
            entry[:values].each do |name, value_type|
              lines << "- `#{name}`: #{value_type}"
            end
          end

          if Array(entry[:actions]).any?
            lines << "" << "## Actions"
            Array(entry[:actions]).each { |action| lines << "- `#{action}`" }
          end

          if Array(entry[:outlets]).any?
            lines << "" << "## Outlets"
            Array(entry[:outlets]).each { |outlet| lines << "- `#{outlet}`" }
          end

          if Array(entry[:classes]).any?
            lines << "" << "## Classes"
            Array(entry[:classes]).each { |klass| lines << "- `#{klass}`" }
          end

          lines.join("\n")
        end
      end
    end
  end
end
