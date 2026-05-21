# frozen_string_literal: true

require 'json'
require 'fileutils'

module RailsAiBridge
  class RubydexAdapter
    # Incremental indexer service for rubydex graphs.
    #
    # On +:build+ performs a full index and records file mtimes.
    # On +:reindex+ detects changed files and either patches the graph
    # incrementally (when changes are below the threshold) or falls back
    # to a full rebuild.
    #
    # Optionally persists file mtimes to disk so change detection works
    # across process restarts.
    class IncrementalIndexer < RailsAiBridge::Service
      MTIMES_FILENAME = 'mtimes.json'

      # Entry point that creates an instance and dispatches the operation.
      #
      # @param operation [Symbol] +:build+ or +:reindex+
      # @param kwargs [Hash] forwarded to {#call}
      # @return [Service::Result]
      def self.call(operation, **)
        new.call(operation, **)
      end

      # Dispatches the indexing operation.
      #
      # @param operation [Symbol] +:build+ or +:reindex+
      # @param root [String] project root directory
      # @param graph [Rubydex::Graph, nil] existing graph (for +:reindex+)
      # @param file_mtimes [Hash<String, Time>] mtimes from last index
      # @param threshold [Float] fallback threshold (0.0-1.0)
      # @param persist [Boolean] whether to persist mtimes
      # @param index_path [String, nil] directory for persistence
      # @return [Service::Result] result with +graph+ and +file_mtimes+ in data
      # @raise [StandardError] rescued and returned as failure result
      def call(operation, root:, graph: nil, file_mtimes: {}, **options)
        threshold = options.fetch(:threshold, 0.3)
        persist = options.fetch(:persist, false)
        index_path = options.fetch(:index_path, nil)

        case operation.to_sym
        when :build
          build(root, threshold, persist, index_path)
        when :reindex
          reindex(root, graph, file_mtimes, threshold, persist, index_path)
        else
          Service::Result.new(false, errors: ["Unsupported operation: #{operation}"])
        end
      rescue StandardError => error
        log_error(operation, error)
        Service::Result.new(false, errors: ["#{self.class} #{operation} failed: #{error.message}"])
      end

      private

      # Performs a full index build, records integer-second mtimes, and
      # optionally persists them to disk.
      #
      # @param root [String] project root directory
      # @param _threshold [Float] unused (present for consistent arity with {#reindex})
      # @param persist [Boolean] whether to write mtimes to disk
      # @param index_path [String, nil] directory for the JSON mtime file
      # @return [Service::Result] success result with +:graph+ and +:file_mtimes+
      def build(root, _threshold, persist, index_path)
        graph = Indexer.build_index(root)
        file_mtimes = record_mtimes(root)
        persist_mtimes(file_mtimes, index_path) if persist && index_path
        Service::Result.new(true, data: { graph: graph, file_mtimes: file_mtimes })
      end

      # Detects changed files and patches the graph incrementally or rebuilds.
      #
      # @param root [String] project root directory
      # @param graph [Object, nil] existing rubydex graph; +nil+ forces a full build
      # @param file_mtimes [Hash<String, Integer>] previously recorded integer-second mtimes
      # @param threshold [Float] change fraction above which a full rebuild is triggered
      # @param persist [Boolean] whether to load/save mtimes to disk
      # @param index_path [String, nil] directory for the JSON mtime file
      # @return [Service::Result] success result with +:graph+ and +:file_mtimes+
      def reindex(root, graph, file_mtimes, threshold, persist, index_path)
        file_mtimes = load_mtimes(index_path) if persist && index_path && file_mtimes.empty?
        rebuild = -> { build(root, threshold, persist, index_path) }
        return rebuild.call unless graph

        changes = changed_files(root, file_mtimes)
        return Service::Result.new(true, data: { graph: graph, file_mtimes: file_mtimes }) if changes.empty?

        total = current_files(root).size
        return rebuild.call if threshold_exceeded?(changes.size, total, threshold)

        apply_incremental_changes(graph, changes, root)
        updated_mtimes = update_mtimes(file_mtimes, root, changes)
        persist_mtimes(updated_mtimes, index_path) if persist && index_path
        Service::Result.new(true, data: { graph: graph, file_mtimes: updated_mtimes })
      end

      # Iterates over changed paths, updating the graph in-place.
      # Calls +graph.resolve+ afterwards if supported.
      #
      # @param graph [Object] existing rubydex graph
      # @param changes [Array<String>] paths of added, modified, or removed files
      # @param root [String] project root directory
      # @return [void]
      def apply_incremental_changes(graph, changes, root)
        current_set = current_files(root).to_set

        changes.each do |path|
          if current_set.include?(path)
            reindex_file(graph, path)
          else
            remove_file(graph, path)
          end
        end

        graph.resolve if graph.respond_to?(:resolve)
      end

      # Re-indexes a single modified file into the graph.
      # No-op when the graph does not support +delete_document+ or +index_source+.
      #
      # @param graph [Object] rubydex graph
      # @param path [String] absolute file path
      # @return [void]
      def reindex_file(graph, path)
        return unless graph.respond_to?(:delete_document) && graph.respond_to?(:index_source)

        graph.delete_document(path) if graph.document(path)
        source = File.read(path, encoding: 'UTF-8')
        graph.index_source(path, source, 'ruby')
      rescue Errno::ENOENT, ArgumentError
        nil
      end

      # Removes a deleted file from the graph.
      # No-op when the graph does not support +delete_document+.
      #
      # @param graph [Object] rubydex graph
      # @param path [String] absolute file path
      # @return [void]
      def remove_file(graph, path)
        return unless graph.respond_to?(:delete_document)

        graph.delete_document(path)
      end

      # Returns paths of files that were added, modified, or removed since the
      # last recorded snapshot.
      #
      # @param root [String] project root directory
      # @param file_mtimes [Hash<String, Integer>] recorded integer-second mtime map
      # @return [Array<String>] changed file paths
      def changed_files(root, file_mtimes)
        return [] if file_mtimes.empty?

        current = current_files(root)
        modified = find_modified_files(current, file_mtimes)
        removed = file_mtimes.keys - current
        modified.concat(removed)
      end

      # Returns files whose integer-second mtime differs from the snapshot.
      #
      # @param current_files [Array<String>] current source file paths
      # @param file_mtimes [Hash<String, Integer>] recorded integer-second mtime map
      # @return [Array<String>]
      def find_modified_files(current_files, file_mtimes)
        current_files.reject do |path|
          file_mtimes.key?(path) && file_mtimes[path] == file_mtime(path)
        end
      end

      # Returns all Ruby source files under +root+.
      #
      # @param root [String] project root directory
      # @return [Array<String>]
      def current_files(root)
        Indexer.source_files(root)
      end

      # Returns +true+ when the fraction of changed files meets or exceeds the
      # threshold, or when +total_count+ is zero (avoids division-by-zero).
      #
      # @param changed_count [Integer] number of changed files
      # @param total_count [Integer] total number of source files
      # @param threshold [Float] fractional limit
      # @return [Boolean]
      def threshold_exceeded?(changed_count, total_count, threshold)
        return true if total_count.zero? && changed_count.positive?

        changed_count.to_f / total_count > threshold
      end

      # Builds an integer-second mtime snapshot for all current source files.
      #
      # @param root [String] project root directory
      # @return [Hash<String, Integer>] path → integer-second mtime map
      def record_mtimes(root)
        current_files(root).index_with { |path| file_mtime(path) }
      end

      # Returns an updated mtime map that reflects the given set of changes.
      # Removed files are dropped; added/modified files get a fresh mtime.
      #
      # @param file_mtimes [Hash<String, Integer>] existing mtime map
      # @param root [String] project root directory
      # @param changes [Array<String>] paths that changed
      # @return [Hash<String, Integer>] updated mtime map
      def update_mtimes(file_mtimes, root, changes)
        current = current_files(root).to_set
        updated = file_mtimes.dup

        changes.each do |path|
          if current.include?(path)
            updated[path] = file_mtime(path)
          else
            updated.delete(path)
          end
        end

        updated
      end

      # Returns the integer-second mtime for a single file.
      # Storing as integers avoids IEEE 754 float-precision loss during JSON
      # serialization round-trips, eliminating spurious "file changed" detections.
      #
      # @param path [String] absolute file path
      # @return [Integer, nil] +nil+ if the file no longer exists
      def file_mtime(path)
        File.mtime(path).to_i
      rescue Errno::ENOENT
        nil
      end

      # Writes the mtime map as JSON to disk, creating the directory if needed.
      #
      # @param file_mtimes [Hash<String, Integer>] integer-second mtime map
      # @param index_path [String, nil] target directory; no-op if +nil+
      # @return [void]
      def persist_mtimes(file_mtimes, index_path)
        return unless index_path

        FileUtils.mkdir_p(index_path)
        File.write(mtimes_path(index_path), JSON.dump(serialize_mtimes(file_mtimes)))
      rescue StandardError => error
        log_error(:persist_mtimes, error)
      end

      # Reads the persisted mtime map from the JSON file.
      #
      # @param index_path [String, nil] directory containing the mtime file
      # @return [Hash<String, Integer>] empty hash when the file does not exist
      def load_mtimes(index_path)
        return {} unless index_path

        path = mtimes_path(index_path)
        return {} unless File.exist?(path)

        deserialize_mtimes(File.read(path))
      rescue StandardError => error
        log_error(:load_mtimes, error)
        {}
      end

      # Builds the full path to the JSON mtime file.
      #
      # @param index_path [String] the index directory
      # @return [String]
      def mtimes_path(index_path)
        File.join(index_path, MTIMES_FILENAME)
      end

      # Converts the mtime map to a JSON-safe hash of integer seconds.
      # Integer seconds round-trip losslessly through JSON, unlike floats.
      #
      # @param file_mtimes [Hash<String, Integer>]
      # @return [Hash<String, Integer>]
      def serialize_mtimes(file_mtimes)
        file_mtimes.transform_values { |time| time&.to_i }
      end

      # Parses the raw JSON hash back to an integer-second mtime map.
      #
      # @param content [String] raw JSON string
      # @return [Hash<String, Integer>]
      def deserialize_mtimes(content)
        json = JSON.parse(content).compact
        json.transform_values { |timestamp| timestamp&.to_i }
      end

      # Logs an error via Rails.logger when available.
      #
      # @param operation [Symbol] the operation that failed
      # @param error [StandardError] the raised exception
      # @return [void]
      def log_error(operation, error)
        logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
        return unless logger

        trace = Array(error.backtrace).first(5).join("\n")
        logger.error("[#{self.class}] #{operation}: #{error.message}\n#{trace}")
      end
    end
  end
end
