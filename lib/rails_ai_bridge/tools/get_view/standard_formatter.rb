# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Formats a standard list of templates and partials.
      class StandardFormatter < BaseFormatter
        # @return [String] The formatted standard output.
        def call
          filtered = filter_view_data
          return "View introspection failed: #{filtered[:error]}" if filtered[:error]

          lines = [heading, '']
          lines << "- Layouts: #{filtered[:layouts].join(', ')}" if filtered[:layouts].any?
          lines << "- Template engines: #{filtered[:template_engines].join(', ')}" if filtered[:template_engines].any?

          if filtered[:templates].any? && !(@partial.present? && @controller.blank?)
            lines << '' << '## Templates by controller'
            filtered[:templates].keys.sort.each do |name|
              lines << "- `#{name}/`: #{filtered[:templates][name].join(', ')}"
            end
          end

          if filtered[:shared_partials].any?
            lines << '' << '## Shared Partials'
            filtered[:shared_partials].each { |name| lines << "- `#{name}`" }
          end

          if filtered[:controller_partials].any?
            lines << '' << '## Controller Partials'
            filtered[:controller_partials].keys.sort.each do |name|
              lines << "- `#{name}/`: #{filtered[:controller_partials][name].join(', ')}"
            end
          end

          lines.join("\n")
        end
      end
    end
  end
end
