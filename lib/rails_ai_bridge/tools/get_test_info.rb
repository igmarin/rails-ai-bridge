# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetTestInfo < BaseTool
      tool_name "rails_get_test_info"
      description "Get test infrastructure information including framework, factories/fixtures, CI config, and coverage setup."

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil)
        data = cached_context[:tests]
        return text_response("Test introspection not available. Add :tests to introspectors.") unless data
        return text_response("Test introspection failed: #{data[:error]}") if data[:error]

        lines = [ "# Test Infrastructure", "" ]
        lines << "- **Framework:** #{data[:framework]}"
        lines << "- **Factories:** #{data[:factories][:location]} (#{data[:factories][:count]} files)" if data[:factories]
        lines << "- **Fixtures:** #{data[:fixtures][:location]} (#{data[:fixtures][:count]} files)" if data[:fixtures]
        lines << "- **System tests:** #{data[:system_tests][:location]}" if data[:system_tests]
        lines << "- **CI:** #{data[:ci_config].join(', ')}" if data[:ci_config]&.any?
        lines << "- **Coverage:** #{data[:coverage]}" if data[:coverage]

        if data[:test_helpers]&.any?
          lines << "" << "## Test Helpers"
          data[:test_helpers].each { |h| lines << "- `#{h}`" }
        end

        text_response(lines.join("\n"))
      end
    end
  end
end
