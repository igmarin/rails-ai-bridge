# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Notable Gems section grouped by category.
      class GemsFormatter < Base
        # @return [String, nil]
        def call
          gems = context[:gems]
          return unless gems
          return if gems[:error]

          notable = gems[:notable_gems] || []
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
