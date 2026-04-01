# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Overview section with architecture and patterns.
      class AppOverviewFormatter < Base
        # @return [String]
        def call
          conv = context[:conventions] || {}
          arch = conv[:architecture] || []
          patterns = conv[:patterns] || []

          lines = [ "## Overview" ]
          lines << "- **Architecture:** #{arch.join(', ')}" if arch.any?
          lines << "- **Patterns:** #{patterns.join(', ')}" if patterns.any?
          lines.join("\n")
        end
      end
    end
  end
end
