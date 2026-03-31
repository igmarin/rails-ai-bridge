# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Testing section with framework, factories, and CI config.
      class TestsFormatter < Base
        # @return [String, nil]
        def call
          data = context[:tests]
          return unless data
          return if data[:error]

          lines = [ "## Testing" ]
          lines << "- Framework: #{data[:framework]}"
          lines << "- Factories: #{data[:factories][:location]} (#{data[:factories][:count]} files)" if data[:factories]
          lines << "- Fixtures: #{data[:fixtures][:location]} (#{data[:fixtures][:count]} files)" if data[:fixtures]
          lines << "- System tests: #{data[:system_tests][:location]}" if data[:system_tests]
          lines << "- CI: #{data[:ci_config].join(', ')}" if data[:ci_config]&.any?
          lines << "- Coverage: #{data[:coverage]}" if data[:coverage]
          lines.join("\n")
        end
      end
    end
  end
end
