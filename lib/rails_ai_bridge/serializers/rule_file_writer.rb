# frozen_string_literal: true

require 'fileutils'

module RailsAiBridge
  module Serializers
    # Writes generated Markdown files to disk with a diff guard: a file is
    # written only when its generated content differs from the content on
    # disk, so unchanged files keep their mtime and stay out of VCS diffs.
    class RuleFileWriter
      # @param dir [String] target directory, created recursively if missing
      def initialize(dir)
        @dir = dir
      end

      # Writes each entry whose content differs from the file on disk,
      # creating the target directory first. Entries with +nil+ content are
      # skipped without creating a file.
      #
      # @param files [Hash{String => String, nil}] filenames relative to the target
      #   directory mapped to generated content
      # @return [Hash{Symbol => Array<String>}] +:written+ and +:skipped+ arrays of
      #   absolute file paths
      def call(files)
        FileUtils.mkdir_p(@dir)

        written = []
        skipped = []
        files.each do |filename, content|
          next unless content

          filepath = File.join(@dir, filename)
          if File.exist?(filepath) && File.read(filepath) == content
            skipped << filepath
          else
            File.write(filepath, content)
            written << filepath
          end
        end
        { written: written, skipped: skipped }
      end
    end
  end
end
