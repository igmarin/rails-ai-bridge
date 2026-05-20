# frozen_string_literal: true

module RailsAiBridge
  # Wrapper class for Shopify's rubydex semantic analysis API.
  #
  # Provides a high-level interface for indexing Ruby source files and
  # querying semantic information such as declarations, references,
  # ancestors, and codebase statistics.
  #
  # Rubydex is an optional dependency. When not installed, all query
  # methods return empty results and {.available?} returns +false+.
  class RubydexAdapter
    @mutex = Mutex.new

    # @return [Rubydex::Graph, nil] the underlying rubydex graph instance
    attr_reader :graph

    class << self
      # Whether the rubydex gem is installed and loadable.
      #
      # @return [Boolean]
      # @raise [LoadError] rescued internally, returns false
      def available?
        if @available.nil?
          @available = begin
            require 'rubydex'
            true
          rescue LoadError
            false
          end
        end

        @available
      end

      # Resets the cached availability check (useful in tests).
      #
      # @return [void]
      def reset_availability!
        @available = nil
      end

      # Returns a shared adapter instance, building the index if needed.
      # Thread-safe via +Mutex+.
      #
      # @param root [String] the Rails root path to index
      # @return [RubydexAdapter]
      # @raise [StandardError] on indexing failure (graph set to nil, indexed to false)
      def instance(root = nil)
        @mutex.synchronize do
          root ||= Rails.root.to_s
          @instance = nil if @instance && @instance_root != root
          @instance ||= begin
            @instance_root = root
            new(root).tap(&:index!)
          end
        end
      end

      # Clears the shared instance (useful in tests or when reindexing).
      #
      # @return [void]
      def reset!
        @mutex.synchronize { @instance = nil }
      end
    end

    # @param root [String] the project root directory to index
    def initialize(root)
      @root = root
      @graph = nil
      @indexed = false
      @serializer = Serializer.new(@root)
      @indexer = Indexer.new
      @incremental_indexer = IncrementalIndexer.new
      @method_counter = MethodCounter.new(serializer: @serializer)
    end

    # Builds the rubydex graph index for the project.
    # No-op if rubydex is not available or already indexed.
    #
    # @return [void]
    # @raise [StandardError] rescued internally, sets indexed to false
    def index!
      return if @indexed || !self.class.available?

      @graph = @incremental_indexer.build(@root)
      @indexed = true
    rescue StandardError => error
      log_warning('rubydex.indexing_failed', error.message, error.backtrace)
      @graph = nil
      @indexed = false
    end

    # Re-indexes only changed files since the last index.
    # Falls back to a full rebuild when changes exceed the threshold.
    #
    # @return [void]
    def reindex!
      return unless @indexed && self.class.available?

      @graph = @incremental_indexer.reindex_changed(@root)
    rescue StandardError => error
      log_warning('rubydex.reindex_failed', error.message, error.backtrace)
    end

    # Whether the graph has been successfully indexed.
    #
    # @return [Boolean]
    def indexed?
      @indexed && @graph.present?
    end

    # Search declarations by name using rubydex fuzzy search.
    #
    # @param query [String] search query (e.g. "User", "Foo#bar")
    # @param max_results [Integer] maximum number of results to return
    # @return [Array<Hash>] array of declaration summaries
    # @raise [StandardError] rescued internally, returns empty array
    def search(query, max_results: 20)
      return [] unless indexed?

      results = @graph.search(query)
      results.first(max_results).map { |decl| @serializer.declaration_to_hash(decl) }
    rescue StandardError => error
      log_warning('rubydex.search_failed', error.message, error.backtrace)
      []
    end

    # Get a declaration by its fully qualified name.
    #
    # @param name [String] fully qualified name (e.g. "Foo::Bar")
    # @return [Hash, nil] declaration details or nil if not found
    # @raise [StandardError] rescued internally, returns nil
    def get_declaration(name)
      return nil unless indexed?

      decl = @graph[name]
      return nil unless decl

      @serializer.detailed_declaration_to_hash(decl)
    rescue StandardError
      nil
    end

    # Get all declarations in the graph.
    #
    # @return [Array<Hash>] array of declaration summaries
    # @raise [StandardError] rescued internally, returns empty array
    def all_declarations
      return [] unless indexed?

      @graph.declarations.map { |decl| @serializer.declaration_to_hash(decl) }
    rescue StandardError
      []
    end

    # Get declarations defined in a specific file.
    #
    # @param path [String] relative or absolute file path
    # @return [Array<Hash>] declarations found in the file
    # @raise [StandardError] rescued internally, returns empty array
    def file_declarations(path)
      return [] unless indexed?

      doc = @graph.documents.find { |d| d.uri.end_with?(path) || d.uri == path }
      return [] unless doc

      doc.definitions.map { |defn| @serializer.definition_to_hash(defn) }
    rescue StandardError
      []
    end

    # Get descendants (subclasses/includers) of a declaration.
    #
    # @param name [String] fully qualified name
    # @return [Array<String>] descendant names
    # @raise [StandardError] rescued internally, returns empty array
    def descendants(name)
      return [] unless indexed?

      decl = @graph[name]
      return [] unless decl.respond_to?(:descendants)

      decl.descendants.map(&:name)
    rescue StandardError
      []
    end

    # Get ancestors (superclasses/included modules) of a declaration.
    #
    # @param name [String] fully qualified name
    # @return [Array<String>] ancestor names
    # @raise [StandardError] rescued internally, returns empty array
    def ancestors(name)
      return [] unless indexed?

      decl = @graph[name]
      return [] unless decl.respond_to?(:ancestors)

      decl.ancestors.map(&:name)
    rescue StandardError
      []
    end

    # Get all constant references across the codebase.
    #
    # @return [Array<Hash>] constant reference details
    # @raise [StandardError] rescued internally, returns empty array
    def constant_references
      return [] unless indexed?

      @graph.constant_references.map do |ref|
        { name: ref.respond_to?(:name) ? ref.name : ref.to_s,
          location: ref.respond_to?(:location) ? @serializer.format_location(ref.location) : nil }.compact
      end
    rescue StandardError
      []
    end

    # High-level codebase statistics from the rubydex index.
    #
    # @return [Hash] statistics about the indexed codebase
    # @raise [StandardError] rescued internally, returns empty hash
    def codebase_stats
      return {} unless indexed?

      declarations = @graph.declarations.to_a
      documents = @graph.documents.to_a

      classes = declarations.select { |d| class_declaration?(d) }
      modules = declarations.select { |d| module_declaration?(d) }

      {
        total_files: documents.size,
        total_declarations: declarations.size,
        total_classes: classes.size,
        total_modules: modules.size,
        total_methods: @method_counter.count(declarations),
        total_constant_references: safe_count(@graph, :constant_references),
        total_method_references: safe_count(@graph, :method_references)
      }
    rescue StandardError
      {}
    end

    private

    def log_warning(event, message, backtrace)
      logger = defined?(Rails) ? Rails.logger : nil
      return unless logger

      trace = Array(backtrace).first(5).join("\n")
      logger.warn("[#{@root}] #{event}: #{message}\n#{trace}")
    end

    def class_declaration?(decl)
      @serializer.declaration_type(decl) == 'class'
    end

    def module_declaration?(decl)
      @serializer.declaration_type(decl) == 'module'
    end

    def safe_count(graph, method)
      return 0 unless graph.respond_to?(method)

      graph.send(method).count
    rescue StandardError
      0
    end
  end
end
