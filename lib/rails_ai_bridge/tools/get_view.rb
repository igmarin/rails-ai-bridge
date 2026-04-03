# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Exposes view-layer context through MCP with compact listings and
    # file-focused inspection for editing workflows.
    class GetView < BaseTool
      tool_name "rails_get_view"
      description "Get view-layer information including layouts, templates, partials, helpers, and components. Optionally inspect a specific view file or filter by controller/partial."

      input_schema(
        properties: {
          path: {
            type: "string",
            description: "Specific view path relative to app/views (for example: 'users/index.html.erb'). Returns edit-focused detail."
          },
          controller: {
            type: "string",
            description: "Optional controller view folder (for example: 'users' or 'admin/reports')."
          },
          partial: {
            type: "string",
            description: "Optional partial name or path fragment (for example: '_form' or 'shared/flash')."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level for listings. summary: counts. standard: template and partial names. full: also helpers and components."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Returns summarized or file-focused view context.
      #
      # @param path [String, nil] view path relative to `app/views`
      # @param controller [String, nil] controller view folder filter
      # @param partial [String, nil] partial name or path fragment filter
      # @param detail [String] one of `summary`, `standard`, or `full`
      # @param server_context [Object, nil] MCP server context
      # @return [MCP::Tool::Response] formatted view information
      def self.call(path: nil, controller: nil, partial: nil, detail: "standard", server_context: nil)
        data = cached_section(:views)
        return text_response("View introspection not available. Add :views to introspectors.") unless data
        return text_response("View introspection failed: #{data[:error]}") if data[:error]

        if path
          analysis = ViewFileAnalyzer.call(root: rails_app.root, relative_path: path)
          return text_response(SpecificViewFormatter.new.call(analysis))
        end

        formatter = build_formatter(detail, data, controller, partial)
        text_response(formatter.call)
      rescue SecurityError => e
        text_response(e.message)
      rescue Errno::ENOENT
        text_response("Path not found: #{path}")
      end

      private_class_method def self.build_formatter(detail, data, controller, partial)
        case detail
        when "summary"
          SummaryFormatter.new(context: data, controller: controller, partial: partial)
        when "full"
          FullFormatter.new(context: data, controller: controller, partial: partial)
        else
          StandardFormatter.new(context: data, controller: controller, partial: partial)
        end
      end
    end
  end
end
