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
            EnforcedLines.new(lines, @config.claude_max_lines).to_a
          end

          # Applies a line budget while preserving room for the trim notice.
          class EnforcedLines
            # @param lines [Array<String>] Full document lines
            # @param max_lines [Integer] Maximum line count allowed in the output
            def initialize(lines, max_lines)
              @lines = lines
              @max_lines = max_lines
            end

            # @return [Array<String>] Original lines, or trimmed lines with the MCP pointer
            def to_a
              return @lines.first(line_budget) if within_limit?
              return [] if line_budget.zero?
              return [LineEnforcer::TRIMMER_NOTICE] if line_budget == 1

              @lines.first(safe_count) + ['', LineEnforcer::TRIMMER_NOTICE]
            end

            private

            # @return [Boolean] true when no trimming is required
            def within_limit?
              @lines.size <= line_budget
            end

            # @return [Integer] Number of source lines to keep before the notice
            def safe_count
              line_budget - 2
            end

            # @return [Integer] Non-negative maximum line budget
            def line_budget
              [@max_lines.to_i, 0].max
            end
          end
        end
      end
    end
  end
end
