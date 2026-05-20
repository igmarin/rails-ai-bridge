# frozen_string_literal: true

module RailsAiBridge
  class RubydexAdapter
    # Tracks file mtimes to detect when reindexing is needed.
    #
    # On the first call, delegates to {Indexer.build_index} for a full build.
    # On subsequent calls via {#reindex_changed}, detects files that have been
    # added, removed, or modified since the last index and triggers a full
    # rebuild when changes are detected. True incremental graph patching
    # requires upstream rubydex support; this class provides the change-
    # detection foundation so that a no-op fast path is taken when no
    # files have changed.
    class IncrementalIndexer
      def initialize
        @file_mtimes = {}
        @graph = nil
      end

      # Performs a full index build and records file mtimes.
      #
      # @param root [String] project root directory
      # @return [Object] the rubydex graph
      def build(root)
        @graph = Indexer.build_index(root)
        record_mtimes(root)
        @graph
      end

      # Rebuilds the index when files have changed since the last build.
      # Returns the cached graph immediately when nothing has changed.
      #
      # @param root [String] project root directory
      # @return [Object] the rubydex graph
      def reindex_changed(root)
        return build(root) unless @graph
        return @graph if changed_files(root).empty?

        build(root)
      end

      # Returns files that have been added, removed, or modified since
      # the last index.
      #
      # @param root [String] project root directory
      # @return [Array<String>] changed file paths
      def changed_files(root)
        return [] if @file_mtimes.empty?

        modified_or_added = find_modified_files(root)
        removed = @file_mtimes.keys - Indexer.source_files(root)
        modified_or_added.concat(removed)
      end

      private

      def find_modified_files(root)
        Indexer.source_files(root).reject do |path|
          @file_mtimes.key?(path) && @file_mtimes[path] == file_mtime(path)
        end
      end

      def record_mtimes(root)
        @file_mtimes = Indexer.source_files(root).index_with { |path| file_mtime(path) }
      end

      def file_mtime(path)
        File.mtime(path)
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
