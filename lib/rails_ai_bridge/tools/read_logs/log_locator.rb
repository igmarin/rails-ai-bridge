# frozen_string_literal: true

require 'pathname'

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

        # Resolves the file against the log directory and opens it in binary
        # mode without following a final-component symlink.
        #
        # @return [Array(File, nil), Array(nil, String)] opened file descriptor
        #   plus nil, or nil plus an error message
        def locate
          return empty_error if @file.strip.empty?

          validate_and_open
        rescue Errno::ENOENT
          [nil, "error: log file not found: #{sanitize_filename}"]
        end

        # Opens the validated candidate file in binary mode without following a
        # final-component symlink. The log directory is application-owned and
        # must not be writable by untrusted users; Ruby has no portable openat
        # API for atomically resolving every parent component from a directory
        # descriptor.
        #
        # @param candidate [Pathname] validated file path
        # @return [Array(File, nil)] opened file descriptor plus nil
        # rubocop:disable Style/FileOpen
        def self.open_file(candidate)
          file_io = File.open(candidate, File::RDONLY | File::NOFOLLOW)
          # rubocop:enable Style/FileOpen
          [file_io, nil]
        end

        private

        def empty_error
          [nil, EMPTY_FILE_ERROR]
        end

        def validate_and_open
          candidate = @log_dir.join(@file).expand_path
          error = candidate_error(candidate)
          return [nil, error] if error

          self.class.open_file(candidate.realpath)
        end

        # First rejection reason for the candidate path, if any.
        #
        # @param candidate [Pathname] expanded candidate path
        # @return [String, nil] error message or nil when allowed
        def candidate_error(candidate)
          return "error: path not allowed: #{sanitize_filename}" unless within_log_dir?(candidate)
          return "error: log file not found: #{sanitize_filename}" unless candidate.file?

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

        # Sanitizes the filename for error messages to prevent log injection.
        #
        # @return [String] sanitized filename
        def sanitize_filename
          @file.gsub(%r{[^\w.\-/]}, '_')
        end
      end
    end
  end
end
