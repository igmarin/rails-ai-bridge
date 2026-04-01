# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Project Structure section from directory counts.
      class ConventionsFormatter < SectionFormatter
        section :conventions

        private

        def render(data)
          return unless data[:directory_structure]&.any?

          lines = [ "## Project Structure" ]
          data[:directory_structure].sort.each do |dir, count|
            lines << "- `#{dir}/` — #{count} files"
          end
          lines.join("\n")
        end
      end
    end
  end
end
