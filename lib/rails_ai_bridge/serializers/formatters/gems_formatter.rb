# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Notable Gems section grouped by category.
      class GemsFormatter < SectionFormatter
        section :gems

        private

        def render(data)
          notable = data[:notable_gems] || []
          return if notable.empty?

          lines = [ "## Notable Gems" ]
          notable.group_by { |g| g[:category] }.sort.each do |cat, group|
            lines << "### #{cat.capitalize}"
            group.each { |g| lines << "- **#{g[:name]}** (#{g[:version]}): #{g[:note]}" }
          end
          lines.join("\n")
        end
      end
    end
  end
end
