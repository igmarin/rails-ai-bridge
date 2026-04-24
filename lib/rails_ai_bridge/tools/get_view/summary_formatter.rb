# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Formats a summary of view-layer components.
      class SummaryFormatter < BaseFormatter
        # @return [String] The formatted summary.
        def call
          filtered = filter_view_data
          return "View introspection failed: #{filtered[:error]}" if filtered[:error]

          lines = [heading, '']
          lines[0] = lines[0].sub('# Views', '# View Summary')
          lines << "- Layouts: #{filtered[:layouts].size}"
          lines << "- Template engines: #{filtered[:template_engines].join(', ')}" if filtered[:template_engines].any?
          lines << "- Shared partials: #{filtered[:shared_partials].size}"
          lines << ''

          unless @partial.present? && @controller.blank?
            filtered[:templates].keys.sort.each do |name|
              template_count = filtered[:templates][name].size
              partial_count = filtered[:controller_partials].fetch(name, []).size
              lines << "- **#{name}/** — #{template_count} templates, #{partial_count} partials"
            end
          end

          lines.join("\n")
        end
      end
    end
  end
end
