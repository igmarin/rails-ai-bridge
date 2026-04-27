# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Enforces maximum line limits for AI context documents.
        # Trims content and adds MCP pointer when limits are exceeded.
        class LineEnforcer
          # Notice text for trimmed content
          TRIMMER_NOTICE = '_Context trimmed. Use MCP tools for full details._'

          # @param config [RailsAiBridge::Configuration] Bridge configuration
          def initialize(config)
            @config = config
          end

          # Enforces claude_max_lines by trimming and adding MCP pointer.
          # @param lines [Array<String>] Full document lines
          # @return [Array<String>] Trimmed lines or original if within limit
          def enforce(lines)
            max_lines = @config.claude_max_lines
            return lines if lines.size <= max_lines

            safe_count = [max_lines - 2, 0].max
            trimmed = lines.first(safe_count)
            result = trimmed.dup
            result << ''
            result << TRIMMER_NOTICE
            result
          end
        end
      end
    end
  end
end
