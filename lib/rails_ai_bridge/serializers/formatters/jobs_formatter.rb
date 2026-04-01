# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders Background Jobs, Mailers, and Action Cable Channels sections.
      class JobsFormatter < SectionFormatter
        section :jobs

        private

        def render(data)
          parts = []

          if data[:jobs]&.any?
            parts << "## Background Jobs"
            data[:jobs].each { |j| parts << "- `#{j[:name]}` (queue: #{j[:queue]})" }
          end

          if data[:mailers]&.any?
            parts << "## Mailers"
            data[:mailers].each { |m| parts << "- `#{m[:name]}`: #{m[:actions].join(', ')}" }
          end

          if data[:channels]&.any?
            parts << "## Action Cable Channels"
            data[:channels].each { |c| parts << "- `#{c[:name]}`" }
          end

          parts.join("\n") if parts.any?
        end
      end
    end
  end
end
