# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Migrations section with pending and recent migrations.
      class MigrationsFormatter < SectionFormatter
        section :migrations

        private

        def render(data)
          lines = [ "## Migrations" ]
          lines << "- Total: #{data[:total]}"
          lines << "- Schema version: #{data[:schema_version]}" if data[:schema_version]

          if data[:pending]&.any?
            lines << "### Pending Migrations (#{data[:pending].size})"
            data[:pending].each { |m| lines << "- `#{m[:version]}` #{m[:name]}" }
          end

          if data[:recent]&.any?
            lines << "### Recent Migrations"
            data[:recent].each do |m|
              actions = m[:actions]&.any? ? " (#{m[:actions].join(', ')})" : ""
              lines << "- `#{m[:version]}` #{m[:name]}#{actions}"
            end
          end

          lines.join("\n")
        end
      end
    end
  end
end
