# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Views section with layouts, templates, and helpers.
      #
      # @see Formatters::Providers::SectionFormatter
      class ViewsFormatter < Formatters::Providers::SectionFormatter
        section :views

        private

        def render(data)
          lines = [ "## Views" ]
          lines << "- Layouts: #{data[:layouts].join(', ')}" if data[:layouts]&.any?
          lines << "- Template engines: #{data[:template_engines].join(', ')}" if data[:template_engines]&.any?

          if data[:templates]&.any?
            lines << "### Templates by controller"
            data[:templates].each do |ctrl, templates|
              lines << "- `#{ctrl}/`: #{templates.join(', ')}"
            end
          end

          if data[:helpers]&.any?
            lines << "### Helpers"
            data[:helpers].each { |h| lines << "- `#{h[:file]}`: #{h[:methods].join(', ')}" }
          end

          lines << "- View components: #{data[:view_components].size}" if data[:view_components]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
