# frozen_string_literal: true

module RailsAiBridge
  class RubydexAdapter
    # Tracks file mtimes to support incremental reindexing.
    #
    # On the first call, delegates to {Indexer.build_index} for a full build.
    # On subsequent calls via {#reindex_changed}, detects files that have been
    # added, removed, or modified since the last index. When the ratio of
    # changed files exceeds {#full_rebuild_threshold} (default 30%), a full
    # rebuild is performed instead of an incremental update.
    class IncrementalIndexer
      # @return [Float] ratio of changed files that triggers a full rebuild
      attr_reader :full_rebuild_threshold

      # @param full_rebuild_threshold [Float] ratio (0.0–1.0) of changed files
      #   above which a full rebuild is preferred over incremental updates
      def initialize(full_rebuild_threshold: 0.3)
        @full_rebuild_threshold = full_rebuild_threshold
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

      # Re-indexes only changed files, or falls back to a full rebuild
      # when too many files have changed or no prior index exists.
      #
      # @param root [String] project root directory
      # @return [Object] the rubydex graph
      def reindex_changed(root)
        return build(root) unless @graph

        changed = changed_files(root)
        return @graph if changed.empty?

        total = Indexer.source_files(root).size
        return build(root) if should_full_rebuild?(changed.size, total)

        build(root)
      end

      # Returns files that have been added, removed, or modified since
      # the last index.
      #
      # @param root [String] project root directory
      # @return [Array<String>] changed file paths
      def changed_files(root)
        return [] if @file_mtimes.empty?

        current_files = Indexer.source_files(root)
        changed = []

        current_files.each do |path|
          mtime = safe_mtime(path)
          old_mtime = @file_mtimes[path]
          changed << path if old_mtime.nil? || mtime != old_mtime
        end

        removed = @file_mtimes.keys - current_files
        changed.concat(removed)

        changed
      end

      private

      def record_mtimes(root)
        @file_mtimes = {}
        Indexer.source_files(root).each do |path|
          @file_mtimes[path] = safe_mtime(path)
        end
      end

      def safe_mtime(path)
        File.mtime(path)
      rescue Errno::ENOENT
        nil
      end

      def should_full_rebuild?(changed_count, total_count)
        return true if total_count.zero?

        (changed_count.to_f / total_count) > @full_rebuild_threshold
      end
    end
  end
end
