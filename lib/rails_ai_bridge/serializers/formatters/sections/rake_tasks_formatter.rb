# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Rake Tasks section.
      #
      # @see Formatters::Providers::SectionFormatter
      class RakeTasksFormatter < Formatters::Providers::SectionFormatter
        section :rake_tasks

        private

        def render(data)
          return unless data[:tasks]&.any?

          lines = [ "## Rake Tasks" ]
          data[:tasks].each do |task|
            desc = task[:description] ? " — #{task[:description]}" : ""
            lines << "- `#{task[:name]}`#{desc}"
          end
          lines.join("\n")
        end
      end
    end
  end
end
