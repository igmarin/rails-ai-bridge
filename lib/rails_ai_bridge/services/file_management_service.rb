# frozen_string_literal: true

require "fileutils"

module RailsAiBridge
  class FileManagementService < Service
    def self.call(operation, **kwargs)
      new.call(operation, **kwargs)
    end

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
        Service::Result.new(false, errors: [ "Unsupported operation: #{operation}" ])
      end
    end

    private

    def write_file(path:, content:)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      Service::Result.new(true, data: { path: path, bytes_written: content.bytesize })
    rescue StandardError => e
      Service::Result.new(false, errors: [ e.message ])
    end

    def read_file(path:)
      content = File.read(path)
      Service::Result.new(true, data: content)
    rescue StandardError => e
      Service::Result.new(false, errors: [ e.message ])
    end

    def delete_file(path:)
      File.delete(path)
      Service::Result.new(true, data: { path: path, deleted: true })
    rescue StandardError => e
      Service::Result.new(false, errors: [ e.message ])
    end

    def file_exists?(path:)
      exists = File.exist?(path)
      Service::Result.new(true, data: exists)
    rescue StandardError => e
      Service::Result.new(false, errors: [ e.message ])
    end
  end
end
