# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class ReadLogs
      # Resolves a client-supplied relative file name to a path under the app's
      # +log/ directory and rejects anything that would escape it.
      class LogLocator
        EMPTY_FILE_ERROR = 'error: file name must not be empty'

        # @param file [Object] raw client-provided file name (relative to log/)
        # @param root [String] application root path
        def initialize(file, root)
          @file = file.to_s
          @log_dir = Pathname.new(File.expand_path(File.join(root, 'log')))
        end

        # Resolves the file against the log directory.
        #
        # @return [Array(Pathname, nil), Array(nil, String)] resolved log path
        #   plus nil, or nil plus an error message
        def locate
          return [nil, EMPTY_FILE_ERROR] if @file.strip.empty?

          candidate = @log_dir.join(@file).expand_path
          error = candidate_error(candidate)
          error ? [nil, error] : [candidate, nil]
        end

        private

        # First rejection reason for the candidate path, if any.
        #
        # @param candidate [Pathname] expanded candidate path
        # @return [String, nil] error message or nil when allowed
        def candidate_error(candidate)
          return "error: path not allowed: #{@file}" unless within_log_dir?(candidate)
          return "error: log file not found: #{@file}" unless candidate.file?

          nil
        end

        # Prefix check on symlink-resolved paths — rejects ../, absolute paths,
        # and dot-segment tricks in one move.
        #
        # @param candidate [Pathname] expanded candidate path
        # @return [Boolean]
        def within_log_dir?(candidate)
          real_dir = begin
            @log_dir.realpath
          rescue Errno::ENOENT
            @log_dir
          end
          resolved = begin
            candidate.realpath
          rescue Errno::ENOENT
            candidate
          end
          resolved.to_s.start_with?("#{real_dir}#{File::SEPARATOR}")
        end
      end
    end
  end
end
