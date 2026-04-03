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

        return specific_view_response(path) if path

        filtered = filter_view_data(data, controller: controller, partial: partial)
        return text_response(filtered[:error]) if filtered[:error]

        case detail
        when "summary"
          text_response(format_summary(filtered, controller: controller, partial: partial))
        when "full"
          text_response(format_full(filtered, controller: controller, partial: partial))
        else
          text_response(format_standard(filtered, controller: controller, partial: partial))
        end
      end

      private_class_method def self.specific_view_response(path)
        analysis = ViewFileAnalyzer.call(root: rails_app.root, relative_path: path)
        text_response(format_specific_view(analysis))
      rescue SecurityError => e
        text_response(e.message)
      rescue Errno::ENOENT
        text_response("Path not found: #{path}")
      end

      private_class_method def self.filter_view_data(data, controller:, partial:)
        filtered = base_view_data(data)
        filtered = apply_controller_filter(filtered, controller)
        return filtered if filtered[:error]

        filtered = apply_partial_filter(filtered, partial)
        return filtered if filtered[:error]

        filtered
      end

      private_class_method def self.base_view_data(data)
        {
          layouts: Array(data[:layouts]),
          template_engines: Array(data[:template_engines]),
          templates: (data[:templates] || {}).dup,
          shared_partials: Array(data.dig(:partials, :shared)).dup,
          controller_partials: (data.dig(:partials, :per_controller) || {}).dup,
          helpers: Array(data[:helpers]),
          view_components: Array(data[:view_components])
        }
      end

      private_class_method def self.apply_controller_filter(filtered, controller)
        return filtered unless controller

        controller_key = controller_key_for(filtered, controller)
        return { error: "Controller views '#{controller}' not found." } unless controller_key

        filtered.merge(
          templates: filtered[:templates].slice(controller_key),
          controller_partials: filtered[:controller_partials].slice(controller_key)
        )
      end

      private_class_method def self.controller_key_for(filtered, controller)
        filtered[:templates].keys.find { |name| name.casecmp?(controller) } ||
          filtered[:controller_partials].keys.find { |name| name.casecmp?(controller) }
      end

      private_class_method def self.apply_partial_filter(filtered, partial)
        return filtered unless partial

        matcher = normalize_partial_matcher(partial)
        shared_partials = filtered[:shared_partials].select { |name| partial_match?(name, matcher) }
        controller_partials = filter_controller_partials(filtered[:controller_partials], matcher)

        return { error: "Partial '#{partial}' not found." } if shared_partials.empty? && controller_partials.empty?

        filtered.merge(shared_partials: shared_partials, controller_partials: controller_partials)
      end

      private_class_method def self.filter_controller_partials(controller_partials, matcher)
        controller_partials.each_with_object({}) do |(name, files), memo|
          matches = files.select { |file| partial_match?(file, matcher) }
          memo[name] = matches if matches.any?
        end
      end

      private_class_method def self.normalize_partial_matcher(partial)
        partial.to_s.sub(%r{\A/+}, "").sub(/\A_/, "")
      end

      private_class_method def self.partial_match?(name, matcher)
        normalized = name.to_s.sub(/\A_/, "")
        normalized.include?(matcher) || name.include?(matcher)
      end

      private_class_method def self.heading(controller:, partial:)
        return "# Views for #{controller}" if controller
        return "# Partials matching #{partial}" if partial

        "# Views"
      end

      private_class_method def self.format_summary(filtered, controller:, partial:)
        lines = [ heading(controller: controller, partial: partial), "" ]
        lines[0] = lines[0].sub("# Views", "# View Summary")
        lines << "- Layouts: #{filtered[:layouts].size}"
        lines << "- Template engines: #{filtered[:template_engines].join(', ')}" if filtered[:template_engines].any?
        lines << "- Shared partials: #{filtered[:shared_partials].size}"
        lines << ""

        unless partial.present? && controller.blank?
          filtered[:templates].keys.sort.each do |name|
            template_count = filtered[:templates][name].size
            partial_count = filtered[:controller_partials].fetch(name, []).size
            lines << "- **#{name}/** — #{template_count} templates, #{partial_count} partials"
          end
        end

        lines.join("\n")
      end

      private_class_method def self.format_standard(filtered, controller:, partial:)
        lines = [ heading(controller: controller, partial: partial), "" ]
        lines << "- Layouts: #{filtered[:layouts].join(', ')}" if filtered[:layouts].any?
        lines << "- Template engines: #{filtered[:template_engines].join(', ')}" if filtered[:template_engines].any?

        if filtered[:templates].any? && !(partial.present? && controller.blank?)
          lines << "" << "## Templates by controller"
          filtered[:templates].keys.sort.each do |name|
            lines << "- `#{name}/`: #{filtered[:templates][name].join(', ')}"
          end
        end

        if filtered[:shared_partials].any?
          lines << "" << "## Shared Partials"
          filtered[:shared_partials].each { |name| lines << "- `#{name}`" }
        end

        if filtered[:controller_partials].any?
          lines << "" << "## Controller Partials"
          filtered[:controller_partials].keys.sort.each do |name|
            lines << "- `#{name}/`: #{filtered[:controller_partials][name].join(', ')}"
          end
        end

        lines.join("\n")
      end

      private_class_method def self.format_full(filtered, controller:, partial:)
        lines = [ format_standard(filtered, controller: controller, partial: partial) ]

        if filtered[:helpers].any?
          lines << "" << "## Helpers"
          filtered[:helpers].each do |helper|
            methods = Array(helper[:methods]).join(", ")
            lines << "- `#{helper[:file]}`: #{methods}"
          end
        end

        if filtered[:view_components].any?
          lines << "" << "## View Components"
          filtered[:view_components].each { |component| lines << "- `#{component}`" }
        end

        lines.join("\n")
      end

      private_class_method def self.format_specific_view(analysis)
        lines = [ "# View: #{analysis[:path]}", "" ]
        lines << "- Template engine: #{analysis[:template_engine]}" if analysis[:template_engine]
        lines << "- Partial: #{analysis[:partial] ? 'yes' : 'no'}"
        lines << "- Renders: #{analysis[:renders].join(', ')}" if analysis[:renders].any?
        lines << "- Turbo frames: #{analysis[:turbo_frames].join(', ')}" if analysis[:turbo_frames].any?
        lines << "- Stimulus controllers: #{analysis[:stimulus_controllers].join(', ')}" if analysis[:stimulus_controllers].any?
        lines << "- Stimulus actions: #{analysis[:stimulus_actions].join(', ')}" if analysis[:stimulus_actions].any?
        lines << ""
        lines << "## Source"
        lines << "```erb"
        lines << analysis[:content].rstrip
        lines << "```"
        lines.join("\n")
      end
    end
  end
end
