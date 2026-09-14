# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool returning a redacted tail of a log file under the app's +log/
    # directory.
    #
    # Security contract (strictly read-only):
    # - only files under Rails.root/log are readable (expanded-path prefix check,
    #   no ../ traversal)
    # - line cap (MAX_LINES) and per-line byte cap applied before returning
    # - every line is redacted through Registry::MessageSanitizer
    # - errors follow the {"error": message} contract
    class ReadLogs < BaseTool
      tool_name 'rails_read_logs'
      description 'Read the tail of a log file under the Rails app log directory. ' \
                  'Lines are capped and credential patterns are redacted. Useful for ' \
                  'investigating errors, stack traces, and request failures.'

      # Hard upper bound for returned lines regardless of client input.
      MAX_LINES = 400

      # Byte cap for any single returned line.
      MAX_LINE_BYTES = 2000

      # Default detail-level tails.
      LINES_BY_DETAIL = { 'summary' => 0, 'standard' => 50, 'full' => MAX_LINES }.freeze

      # Fallback tail for an unrecognized detail level.
      DEFAULT_LINES = 50

      input_schema(
        properties: {
          file: {
            type: 'string',
            description: 'Log file name relative to the log directory (e.g. "production.log" or "nested/app.log").'
          },
          lines: {
            type: 'integer',
            description: "Tail length in lines (hard cap #{MAX_LINES}). Defaults to 50 " \
                         '(standard detail) or 400 (full detail).'
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'summary: file metadata only (size, mtime, line hint). standard: tail of 50 lines. ' \
                         'full: tail of up to 400 lines.'
          }
        },
        required: ['file']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Returns the redacted tail of the requested log file as compact JSON.
      #
      # @param file [String] log file name relative to the log directory
      # @param lines [Integer, nil] requested tail length (hard-capped at MAX_LINES)
      # @param detail [String] +summary+, +standard+, or +full+
      # @return [MCP::Tool::Response] JSON payload with file metadata and tail
      #   lines, or {"error": "..."}
      # @raise [StandardError] never escapes; converted to an error response
      def self.call(file:, lines: nil, detail: 'standard')
        log_path, error = LogLocator.new(file, Rails.root.to_s).locate
        return error_response(error) if error

        respond(log_path, lines, detail)
      rescue StandardError => error
        execution_failure(error)
      end

      # Builds and formats the response for a located log file.
      #
      # @param log_path [Pathname] resolved log file path
      # @param lines [Integer, nil] requested tail length
      # @param detail [String] detail level
      # @return [MCP::Tool::Response] compact JSON payload
      def self.respond(log_path, lines, detail)
        payload = TailFormatter.new(log_path, lines: lines, detail: detail).format
        text_response(payload.to_json)
      end

      # Builds an error response following the {"error": message} contract.
      #
      # @param message [String] error message
      # @return [MCP::Tool::Response]
      def self.error_response(message)
        text_response({ error: message }.to_json)
      end

      # Logs a failed read with message and backtrace head, then returns the
      # sanitized error.
      #
      # @param error [StandardError] raised error
      # @return [MCP::Tool::Response] sanitized error payload
      def self.execution_failure(error)
        message = error.message
        logger = Rails.logger
        logger.error(message)
        logger.error(error.backtrace.first(5).join("\n"))
        error_response(Registry::MessageSanitizer.sanitize(message))
      end

      # Formats a log tail: file metadata plus the redacted, capped tail lines.
      class TailFormatter
        # @param log_path [Pathname] resolved log file path
        # @param lines [Integer, nil] requested tail length
        # @param detail [String] detail level
        def initialize(log_path, lines:, detail:)
          @log_path = log_path
          @lines = lines
          @detail = detail
        end

        # Builds the payload.
        #
        # @return [Hash] compact payload with +file+, +size_bytes+, +tail_lines+
        def format
          payload = {
            file: @log_path.basename.to_s,
            size_bytes: @log_path.size,
            total_lines: total_lines
          }
          return payload if @detail == 'summary'

          payload.merge(lines: redacted_tail(tail_length))
        end

        private

        # Effective tail length from the request or the detail-level default.
        #
        # @return [Integer]
        def tail_length
          requested = @lines.to_i
          requested = LINES_BY_DETAIL.fetch(@detail, DEFAULT_LINES) if requested < 1
          requested.clamp(1, ReadLogs::MAX_LINES)
        end

        # Number of lines in the file.
        #
        # @return [Integer]
        def total_lines
          @log_path.each_line.count
        end

        # Last +length+ lines, byte-capped per line and redacted.
        #
        # @param length [Integer] number of tail lines
        # @return [Array<String>] redacted tail lines
        def redacted_tail(length)
          @log_path.each_line.to_a.last(length).map do |line|
            trimmed = line.byteslice(0, ReadLogs::MAX_LINE_BYTES)
            Registry::MessageSanitizer.sanitize(trimmed.chomp)
          end
        end
      end
    end
  end
end
