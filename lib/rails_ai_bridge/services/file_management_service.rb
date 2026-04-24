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

      # Expands +path+ and ensures it stays within +base_dir+ (or equals it).
      #
      # Relative paths are resolved from +base_dir+. Absolute paths are normalized and must still fall
      # under +base_dir+.
      #
      # @param path [String, #to_s] filesystem path
      # @param base_dir [String, #to_s] allowed root directory
      # @return [String] expanded absolute path within +base_dir+
      # @raise [ArgumentError] if +path+ is empty
      # @raise [SecurityError] if the expanded path escapes +base_dir+
      def validate_path!(path, base_dir = default_allowed_base_dir)
        path_string = path.to_s
        raise ArgumentError, 'path must be non-empty' if path_string.empty?

        base = File.expand_path(base_dir.to_s)
        expanded = File.expand_path(path_string, base)

        prefix =
          if base.end_with?(File::SEPARATOR)
            base
          else
            "#{base}#{File::SEPARATOR}"
          end

        return expanded if expanded == base || expanded.start_with?(prefix)

        raise SecurityError, "Path not allowed: #{path}"
      end

      # @param path [String] file path (validated)
      # @param content [String] content to write
      # @return [Service::Result]
      def write_file(path:, content:)
        safe_path = validate_path!(path)
        FileUtils.mkdir_p(File.dirname(safe_path))
        File.write(safe_path, content)
        Service::Result.new(true, data: { path: safe_path, bytes_written: content.bytesize })
      rescue SecurityError, StandardError => e
        Service::Result.new(false, errors: [e.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def read_file(path:)
        safe_path = validate_path!(path)
        content = File.read(safe_path)
        Service::Result.new(true, data: content)
      rescue SecurityError, StandardError => e
        Service::Result.new(false, errors: [e.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def delete_file(path:)
        safe_path = validate_path!(path)
        File.delete(safe_path)
        Service::Result.new(true, data: { path: safe_path, deleted: true })
      rescue SecurityError, StandardError => e
        Service::Result.new(false, errors: [e.message])
      end

      # @param path [String] file path (validated)
      # @return [Service::Result]
      def file_exists?(path:)
        safe_path = validate_path!(path)
        exists = File.exist?(safe_path)
        Service::Result.new(true, data: exists)
      rescue SecurityError, StandardError => e
        Service::Result.new(false, errors: [e.message])
      end
    end
  end
end
