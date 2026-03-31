# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Rake Tasks section.
      class RakeTasksFormatter < Base
        # @return [String, nil]
        def call
          data = context[:rake_tasks]
          return unless data
          return if data[:error]
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
