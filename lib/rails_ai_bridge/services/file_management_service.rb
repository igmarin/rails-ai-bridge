# frozen_string_literal: true

require 'fileutils'

module RailsAiBridge
  module Services
    # Application service for file system operations confined to an allowed base directory.
    #
    # All paths are expanded and must lie under {Rails.root} when Rails is loaded, otherwise under
    # {Dir.pwd}. This limits read/write/delete to the application tree and returns failures (including
    # {SecurityError}) as {RailsAiBridge::Service::Result} instead of raising.
    #
    # @example Write a file (relative to allowed base)
    #   result = Services::FileManagementService.call(:write, path: "tmp/config.yml", content: "key: value")
    #   if result.success?
    #     puts "File written successfully"
    #   end
    #
    # @example Read a file
    #   result = Services::FileManagementService.call(:read, path: "config/database.yml")
    #   if result.success?
    #     puts result.data
    #   end
    class FileManagementService < RailsAiBridge::Service
      # @param operation [Symbol, nil] one of +:write+, +:read+, +:delete+, +:exist?+; +nil+ is rejected
      #   with a failure result (see {#call})
      # @param kwargs [Hash] operation-specific arguments (+:path+ required for all supported operations;
      #   +:content+ required for +:write+)
      # @return [RailsAiBridge::Service::Result] success or failure with errors
      def self.call(operation, **)
        new.call(operation, **)
      end

      # Dispatches the file operation after validating +operation+ and (for supported ops) the path.
      #
      # @param operation [Symbol, nil] +:write+, +:read+, +:delete+, +:exist?+, another value (unsupported),
      #   or +nil+. When +nil+, returns failure with error +"Operation cannot be nil"+ and does not touch
      #   the filesystem.
      # @param kwargs [Hash] forwarded to the underlying operation (+:path+, +:content+, etc.)
      # @return [RailsAiBridge::Service::Result]
      def call(operation, **)
        return Service::Result.new(false, errors: ['Operation cannot be nil']) if operation.nil?

        case operation.to_sym
        when :write
          write_file(**)
        when :read
          read_file(**)
        when :delete
          delete_file(**)
        when :exist?
          file_exists?(**)
        else
          Service::Result.new(false, errors: ["Unsupported operation: #{operation}"])
        end
      end

      private

      # @return [String] expanded allowed root directory
      def default_allowed_base_dir
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.to_s
        else
          Dir.pwd
        end
      end

      # Expands +path+ and ensures it stays within +base_dir+ (or equals it), resolving symlinks.
      #
      # Relative paths are resolved from +base_dir+. Absolute paths are normalized and must still fall
      # under +base_dir+. Symlinks are resolved to their real paths to prevent escapes.
      #
      # @param path [String, #to_s] filesystem path
      # @param base_dir [String, #to_s] allowed root directory
      # @param must_exist [Boolean] whether the target path must already exist (uses realpath on target vs parent)
      # @return [String] expanded absolute path within +base_dir+
      # @raise [ArgumentError] if +path+ is empty
      # @raise [SecurityError] if the expanded path escapes +base_dir+
      def validate_path!(path, base_dir = default_allowed_base_dir, must_exist: false)
        path_string = path.to_s
        raise ArgumentError, 'path must be non-empty' if path_string.empty?

        base = File.realpath(base_dir.to_s)
        expanded = File.expand_path(path_string, base)

        # Always resolve the parent if it exists to ensure we're not inside a symlinked directory
        # that points outside the allowed base.
        parent = File.expand_path(File.dirname(expanded))
        parent = File.realpath(parent) if File.exist?(parent)

        # If the file exists, resolve it fully to catch symlinked files pointing outside.
        # If it doesn't exist, we rely on the parent resolution.
        resolved_expanded = File.exist?(expanded) ? File.realpath(expanded) : File.join(parent, File.basename(expanded))

        prefix = base.end_with?(File::SEPARATOR) ? base : "#{base}#{File::SEPARATOR}"
        raise SecurityError, "Path not allowed: #{path}" unless resolved_expanded == base || resolved_expanded.start_with?(prefix)

        raise Errno::ENOENT, "No such file or directory - #{expanded}" if must_exist && !File.exist?(expanded)

        resolved_expanded
      end

      # @param path [String] file path (validated)
      # @param content [String] content to write
      # @return [Service::Result]
      def write_file(path:, content:)
        safe_path = validate_path!(path, must_exist: false)
        FileUtils.mkdir_p(File.dirname(safe_path))
        File.write(safe_path, content)
        Service::Result.new(true, data: { path: safe_path, bytes_written: content.bytesize })
      rescue SecurityError, StandardError => error
        Service::Result.new(false, errors: [error.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def read_file(path:)
        safe_path = validate_path!(path, must_exist: true)
        content = File.read(safe_path)
        Service::Result.new(true, data: content)
      rescue SecurityError, StandardError => error
        Service::Result.new(false, errors: [error.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def delete_file(path:)
        safe_path = validate_path!(path, must_exist: true)
        File.delete(safe_path)
        Service::Result.new(true, data: { path: safe_path, deleted: true })
      rescue SecurityError, StandardError => error
        Service::Result.new(false, errors: [error.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def file_exists?(path:)
        safe_path = validate_path!(path, must_exist: true)
        exists = File.exist?(safe_path)
        Service::Result.new(true, data: exists)
      rescue SecurityError, StandardError => error
        # Re-map ENOENT/SecurityError from validate_path! to a false result for exist?
        return Service::Result.new(true, data: false) if error.is_a?(SecurityError) || error.is_a?(Errno::ENOENT)

        Service::Result.new(false, errors: [error.message])
      end
    end
  end
end
