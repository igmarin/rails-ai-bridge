# frozen_string_literal: true

require "fileutils"

module RailsAiBridge
  # Service for file system operations.
  #
  # Provides a safe, consistent interface for common file operations with
  # proper error handling and result formatting.
  #
  # @example Write a file
  #   result = FileManagementService.call(:write, path: "config.yml", content: "key: value")
  #   if result.success?
  #     puts "File written successfully"
  #   end
  #
  # @example Read a file
  #   result = FileManagementService.call(:read, path: "config.yml")
  #   if result.success?
  #     puts result.data
  #   end
  class FileManagementService < Service
    def self.call(operation, **kwargs)
      new.call(operation, **kwargs)
    end

    # Execute a file operation and return the result.
    #
    # @param operation [Symbol] the operation to perform (:write, :read, :delete, :exist?)
    # @param kwargs [Hash] operation-specific arguments
    # @return [Service::Result] result of the file operation
    def call(operation, **kwargs)
      case operation.to_sym
      when :write
        write_file(**kwargs)
      when :read
        read_file(**kwargs)
      when :delete
        delete_file(**kwargs)
      when :exist?
        file_exists?(**kwargs)
      else
        Service::Result.new(false, errors: ["Unsupported operation: #{operation}"])
      end
    end

    private

    # Write content to a file, creating directories as needed.
    #
    # @param path [String] file path
    # @param content [String] content to write
    # @return [Service::Result] result with file info
    def write_file(path:, content:)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      Service::Result.new(true, data: {path: path, bytes_written: content.bytesize})
    rescue StandardError => e
      Service::Result.new(false, errors: [e.message])
    end

    # Read content from a file.
    #
    # @param path [String] file path
    # @return [Service::Result] result with file content
    def read_file(path:)
      content = File.read(path)
      Service::Result.new(true, data: content)
    rescue StandardError => e
      Service::Result.new(false, errors: [e.message])
    end

    # Delete a file.
    #
    # @param path [String] file path
    # @return [Service::Result] result with deletion status
    def delete_file(path:)
      File.delete(path)
      Service::Result.new(true, data: {path: path, deleted: true})
    rescue StandardError => e
      Service::Result.new(false, errors: [e.message])
    end

    # Check if a file exists.
    #
    # @param path [String] file path
    # @return [Service::Result] result with existence status
    def file_exists?(path:)
      exists = File.exist?(path)
      Service::Result.new(true, data: exists)
    rescue StandardError => e
      Service::Result.new(false, errors: [e.message])
    end
  end
end
