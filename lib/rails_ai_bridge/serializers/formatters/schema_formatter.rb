# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Database Schema section; returns nil when schema is absent or errored.
      class SchemaFormatter < Base
        # @return [String, nil]
        def call
          schema = context[:schema]
          return unless schema
          return if schema[:error]

          lines = [ "## Database Schema (#{schema[:total_tables]} tables)" ]
          schema[:tables]&.each do |name, data|
            cols = (data[:columns] || []).map { |c| "`#{c[:name]}` (#{c[:type]})" }.join(", ")
            lines << "### #{name}"
            lines << cols
          end
          lines.join("\n\n")
        end
      end
    end
  end
end
