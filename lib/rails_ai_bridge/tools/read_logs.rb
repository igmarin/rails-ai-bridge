# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class ReadLogs < BaseTool
      tool_name 'rails_read_logs'
      description 'Read the tail of a log file under the Rails app log directory. ' \
                  'Lines are capped and credential patterns are redacted. Useful for ' \
                  'investigating errors, stack traces, and request failures.'

      MAX_LINES = 400
      MAX_LINE_BYTES = 2000
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
            description: 'summary: file metadata only (size, mtime, line hint). standard: tail of 50 lines. ' \
                         'full: tail of up to 400 lines.'
          }
        },
        required: ['file']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

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
        logger = Rails.logger
        logger.error(message)
        logger.error(error.backtrace.first(5).join("\n"))
        error_response(message)
      end

      class TailFormatter
        def initialize(file_io, lines:, detail:)
          @file_io = file_io
          @lines = lines
          @detail = detail
        end

        def format
          return build_summary if @detail == 'summary'

          build_tail
        ensure
          @file_io.close
        end

        def self.redact(line)
          trimmed = line.force_encoding(Encoding::UTF_8).scrub
          Registry::MessageSanitizer.sanitize(trimmed.chomp)
        end

        def self.append_to_tail(tail_lines, line, cap)
          tail_lines << redact(line)
          tail_lines.shift while tail_lines.size > cap
        end

        private

        def build_summary
          {
            file: File.basename(@file_io.path),
            size_bytes: @file_io.stat.size,
            total_lines: nil
          }
        end

        def build_tail
          tail_lines = []
          cap = tail_length
          total = process_lines(tail_lines, cap)
          build_payload(total, tail_lines)
        end

        def process_lines(tail_lines, cap)
          total = 0
          @file_io.each_line(ReadLogs::MAX_LINE_BYTES) do |line|
            total += 1
            TailFormatter.append_to_tail(tail_lines, line, cap)
          end
          total
        end

        def build_payload(total, tail_lines)
          {
            file: File.basename(@file_io.path),
            size_bytes: @file_io.stat.size,
            total_lines: total,
            lines: tail_lines
          }
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
