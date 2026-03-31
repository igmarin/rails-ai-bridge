# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders Background Jobs, Mailers, and Action Cable Channels sections.
      class JobsFormatter < Base
        # @return [String, nil]
        def call
          jobs = context[:jobs]
          return unless jobs

          parts = []

          if jobs[:jobs]&.any?
            parts << "## Background Jobs"
            jobs[:jobs].each { |j| parts << "- `#{j[:name]}` (queue: #{j[:queue]})" }
          end

          if jobs[:mailers]&.any?
            parts << "## Mailers"
            jobs[:mailers].each { |m| parts << "- `#{m[:name]}`: #{m[:actions].join(', ')}" }
          end

          if jobs[:channels]&.any?
            parts << "## Action Cable Channels"
            jobs[:channels].each { |c| parts << "- `#{c[:name]}`" }
          end

          parts.join("\n") if parts.any?
        end
      end
    end
  end
end
