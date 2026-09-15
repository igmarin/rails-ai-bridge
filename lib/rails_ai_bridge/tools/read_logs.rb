# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool returning a redacted tail of a log file under the app's +log/+
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

      MAX_LINES = 400
      MAX_LINE_BYTES = 2000
      MAX_TAIL_SCAN_BYTES = MAX_LINES * MAX_LINE_BYTES
      LINES_BY_DETAIL = { 'summary' => 0, 'standard' => 50, 'full' => MAX_LINES }.freeze
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
            description: 'summary: file metadata (name, size). standard: tail of 50 lines. ' \
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
        file_io, error = LogLocator.new(file, Rails.root.to_s).locate
        return error_response(error) if error

        respond(file_io, lines, detail)
      rescue StandardError => error
        execution_failure(error)
      end

      private_class_method def self.respond(file_io, lines, detail)
        payload = TailFormatter.new(file_io, lines: lines, detail: detail).format
        text_response(payload.to_json)
      end

      private_class_method def self.error_response(message)
        text_response({ error: message }.to_json)
      end

      private_class_method def self.execution_failure(error)
        message = Registry::MessageSanitizer.sanitize(error.message)
        error_response(message)
      end

      # Formats a log tail: file metadata plus the redacted, capped tail lines.
      #
      # The file is consumed in a single streaming pass; tail lines are kept in
      # a buffer capped at the requested length, so memory stays bounded no
      # matter how large the log file is.
      class TailFormatter
        # @param file_io [File] opened log file descriptor (binary mode)
        # @param lines [Integer, nil] requested tail length
        # @param detail [String] detail level
        def initialize(file_io, lines:, detail:)
          @file_io = file_io
          @lines = lines
          @detail = detail
        end

        # Builds the payload.
        #
        # @return [Hash] compact payload with +file+, +size_bytes+, +total_lines+
        #   and (for non-summary detail) redacted tail +lines+
        def format
          return build_summary if @detail == 'summary'

          build_tail
        ensure
          @file_io.close
        end

        # Byte-caps, scrubs, and redacts a single line.
        #
        # @param line [String] raw line from the log file
        # @return [String] redacted line
        def self.redact(line)
          trimmed = line.force_encoding(Encoding::UTF_8).scrub
          sanitized = Registry::MessageSanitizer.sanitize(trimmed.chomp)
          truncate_utf8(sanitized)
        end

        # Truncates without leaving a partial UTF-8 character at the boundary.
        #
        # @param value [String] valid UTF-8 value
        # @return [String] valid UTF-8 value capped at MAX_LINE_BYTES
        def self.truncate_utf8(value)
          capped = value.byteslice(0, ReadLogs::MAX_LINE_BYTES).force_encoding(Encoding::UTF_8)
          capped = capped.byteslice(0, capped.bytesize - 1).force_encoding(Encoding::UTF_8) until capped.valid_encoding?
          capped
        end
        private_class_method :truncate_utf8

        # Appends a redacted line to the tail buffer, maintaining the cap.
        #
        # @param tail_lines [Array<String>] current tail buffer
        # @param line [String] raw line to redact and append
        # @param cap [Integer] maximum buffer size
        # @return [void]
        def self.append_to_tail(tail_lines, line, cap)
          tail_lines << redact(line)
          tail_lines.shift while tail_lines.size > cap
        end

        private

        def build_summary
          {
            file: relative_path,
            size_bytes: @file_io.stat.size,
            total_lines: nil
          }
        end

        def build_tail
          tail_lines = []
          cap = tail_length
          process_lines(tail_lines, cap, skip_first_record: seek_to_tail_window)
          build_payload(tail_lines)
        end

        # A streaming state machine is necessary here: IO#each_line can split
        # an oversized physical record at MAX_LINE_BYTES.
        # :reek:TooManyStatements
        def process_lines(tail_lines, cap, skip_first_record:)
          in_truncated_line = skip_first_record

          @file_io.each_line(ReadLogs::MAX_LINE_BYTES) do |chunk|
            self.class.append_to_tail(tail_lines, chunk, cap) unless in_truncated_line
            in_truncated_line = !chunk.end_with?("\n")
          end
        end

        def build_payload(tail_lines)
          {
            file: relative_path,
            size_bytes: @file_io.stat.size,
            total_lines: nil,
            lines: tail_lines
          }
        end

        # Seeks to a fixed-size window at the end of the file. When the window
        # starts in the middle of a physical line, that partial record is
        # discarded rather than returned as a misleading tail entry.
        #
        # @return [Boolean] whether the first streamed record is partial
        def seek_to_tail_window
          size = @file_io.stat.size
          return false if size <= ReadLogs::MAX_TAIL_SCAN_BYTES

          start = size - ReadLogs::MAX_TAIL_SCAN_BYTES
          @file_io.seek(start - 1)
          partial_record = @file_io.read(1) != "\n"
          @file_io.seek(start)
          partial_record
        end

        def relative_path
          log_dir = Pathname.new(Rails.root).join('log').to_s
          Pathname.new(@file_io.path).relative_path_from(Pathname.new(log_dir)).to_s
        end

        def tail_length
          requested = @lines.to_i
          requested = LINES_BY_DETAIL.fetch(@detail, DEFAULT_LINES) if requested < 1
          requested.clamp(1, ReadLogs::MAX_LINES)
        end
      end
    end
  end
end
