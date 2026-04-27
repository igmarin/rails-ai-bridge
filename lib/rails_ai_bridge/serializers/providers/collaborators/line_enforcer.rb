# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Enforces maximum line limits for AI context documents.
        # Trims content and adds MCP pointer when limits are exceeded.
        class LineEnforcer
          # @param config [RailsAiBridge::Configuration] Bridge configuration
          def initialize(config)
            @config = config
          end

          # Enforces claude_max_lines by trimming and adding MCP pointer.
          # @param lines [Array<String>] Full document lines
          # @return [Array<String>] Trimmed lines or original if within limit
          def enforce(lines)
            max = @config.claude_max_lines
            return lines if lines.size <= max

            trimmed = lines.first(max - 2)
            trimmed << ''
            trimmed << '_Context trimmed. Use MCP tools for full details._'
            trimmed
          end
        end
      end
    end
  end
end
