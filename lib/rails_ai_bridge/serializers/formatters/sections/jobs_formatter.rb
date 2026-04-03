# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Jobs section with Active Job adapters and defined jobs.
      #
      # @see Formatters::Providers::SectionFormatter
      class JobsFormatter < SectionFormatter
        section :jobs

        private

        def render(data)
          return unless data[:adapter] || data[:jobs]&.any?

          lines = [ "## Jobs (#{data[:total_jobs] || 0})", "" ]
          lines << "- Adapter: `#{data[:adapter]}`" if data[:adapter]

          if data[:jobs]&.any?
            lines << "" << "### Defined Jobs"
            data[:jobs].each { |j| lines << "- `#{j}`" }
          end
          lines.join("\n")
        end
      end
    end
  end
end
