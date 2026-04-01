# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Database Schema section; returns nil when schema is absent or errored.
      class SchemaFormatter < SectionFormatter
        section :schema

        private

        def render(data)
          lines = [ "## Database Schema (#{data[:total_tables]} tables)" ]
          data[:tables]&.each do |name, table|
            cols = (table[:columns] || []).map { |c| "`#{c[:name]}` (#{c[:type]})" }.join(", ")
            lines << "### #{name}"
            lines << cols
          end
          lines.join("\n\n")
        end
      end
    end
  end
end
