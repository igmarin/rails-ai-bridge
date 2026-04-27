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
            LineProcessor.process(lines, @config.claude_max_lines)
          end

          # Utility class for processing lines and enforcing limits
          class LineProcessor
            def self.process(lines, max_lines)
              return lines if lines.size <= max_lines

              trimmed = LineTrimmer.trim(lines, max_lines)
              LineAppender.add_trimmer_notice(trimmed)
            end
          end

          # Utility class for trimming lines to specified limit
          class LineTrimmer
            def self.trim(lines, max_lines)
              lines.first(max_lines - 2)
            end
          end

          # Utility class for appending trimmer notice
          class LineAppender
            TRIMMER_NOTICE = '_Context trimmed. Use MCP tools for full details._'

            def self.add_trimmer_notice(lines)
              result = lines.dup
              result << ''
              result << TRIMMER_NOTICE
              result
            end
          end
        end
      end
    end
  end
end
