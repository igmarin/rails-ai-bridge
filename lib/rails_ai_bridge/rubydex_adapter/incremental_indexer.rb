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

      def build(root, _threshold, persist, index_path)
        graph = Indexer.build_index(root)
        file_mtimes = record_mtimes(root)
        persist_mtimes(file_mtimes, index_path) if persist && index_path
        Service::Result.new(true, data: { graph: graph, file_mtimes: file_mtimes })
      end

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

      def reindex_file(graph, path)
        return unless graph.respond_to?(:delete_document) && graph.respond_to?(:index_source)

        graph.delete_document(path) if graph.document(path)
        source = File.read(path, encoding: 'UTF-8')
        graph.index_source(path, source, 'ruby')
      rescue Errno::ENOENT, ArgumentError
        nil
      end

      def remove_file(graph, path)
        return unless graph.respond_to?(:delete_document)

        graph.delete_document(path)
      end

      def changed_files(root, file_mtimes)
        return [] if file_mtimes.empty?

        current = current_files(root)
        modified = find_modified_files(current, file_mtimes)
        removed = file_mtimes.keys - current
        modified.concat(removed)
      end

      def find_modified_files(current_files, file_mtimes)
        current_files.reject do |path|
          file_mtimes.key?(path) && file_mtimes[path] == file_mtime(path)
        end
      end

      def current_files(root)
        Indexer.source_files(root)
      end

      def threshold_exceeded?(changed_count, total_count, threshold)
        return true if total_count.zero? && changed_count.positive?

        changed_count.to_f / total_count > threshold
      end

      def record_mtimes(root)
        current_files(root).index_with { |path| file_mtime(path) }
      end

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

      def file_mtime(path)
        File.mtime(path)
      rescue Errno::ENOENT
        nil
      end

      def persist_mtimes(file_mtimes, index_path)
        return unless index_path

        FileUtils.mkdir_p(index_path)
        File.write(mtimes_path(index_path), JSON.dump(serialize_mtimes(file_mtimes)))
      rescue StandardError => error
        log_error(:persist_mtimes, error)
      end

      def load_mtimes(index_path)
        return {} unless index_path

        path = mtimes_path(index_path)
        return {} unless File.exist?(path)

        deserialize_mtimes(File.read(path))
      rescue StandardError => error
        log_error(:load_mtimes, error)
        {}
      end

      def mtimes_path(index_path)
        File.join(index_path, MTIMES_FILENAME)
      end

      def serialize_mtimes(file_mtimes)
        file_mtimes.transform_values { |time| time&.to_f }
      end

      def deserialize_mtimes(content)
        json = JSON.parse(content).compact
        json.transform_values { |timestamp| Time.at(timestamp).utc }
      end

      def log_error(operation, error)
        logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
        return unless logger

        trace = Array(error.backtrace).first(5).join("\n")
        logger.error("[#{self.class}] #{operation}: #{error.message}\n#{trace}")
      end
    end
  end
end
