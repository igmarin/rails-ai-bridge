# frozen_string_literal: true

module RailsAiBridge
  class RubydexAdapter
    # Builds the rubydex graph index from Ruby source files.
    #
    # Scans a project root for +.rb+ files, excluding common
    # non-source directories, creates a graph, indexes all
    # matching files, and resolves references.
    class Indexer
      EXCLUDED_DIRS = %w[node_modules tmp log vendor .git .bundle].freeze

      # Builds and returns a resolved rubydex graph for the given root.
      #
      # @param root [String] the project root directory path
      # @return [Rubydex::Graph] indexed and resolved graph
      # @raise [StandardError] when indexing or resolving fails
      def build(root)
        graph = ::Rubydex::Graph.new
        graph.index_all(source_files(root))
        graph.resolve
        graph
      end

      private

      # Collects all non-excluded Ruby source files under the project root.
      #
      # @param root [String] the project root directory path
      # @return [Array<String>] absolute file paths
      def source_files(root)
        Dir.glob(File.join(root, '**', '*.rb')).reject do |path|
          EXCLUDED_DIRS.any? { |dir| path.include?("/#{dir}/") }
        end
      end
    end
  end
end
