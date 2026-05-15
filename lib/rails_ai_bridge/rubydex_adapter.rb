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
    # @return [Rubydex::Graph, nil] the underlying rubydex graph instance
    attr_reader :graph

    class << self
      # Whether the rubydex gem is installed and loadable.
      #
      # @return [Boolean]
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
      def instance(root = nil)
        @mutex ||= Mutex.new
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
        @mutex&.synchronize { @instance = nil }
      end
    end

    # @param root [String] the project root directory to index
    def initialize(root)
      @root = root
      @graph = nil
      @indexed = false
    end

    # Builds the rubydex graph index for the project.
    # No-op if rubydex is not available or already indexed.
    #
    # @return [void]
    def index!
      return if @indexed || !self.class.available?

      @graph = ::Rubydex::Graph.new
      @graph.index_all(ruby_source_files)
      @graph.resolve
      @indexed = true
    rescue StandardError => error
      Rails.logger.warn "[rails-ai-bridge] Rubydex indexing failed: #{error.message}"
      @graph = nil
      @indexed = false
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
    def search(query, max_results: 20)
      return [] unless indexed?

      results = @graph.search(query)
      results.first(max_results).map { |decl| declaration_to_hash(decl) }
    rescue StandardError => error
      Rails.logger.warn "[rails-ai-bridge] Rubydex search failed: #{error.message}"
      []
    end

    # Get a declaration by its fully qualified name.
    #
    # @param name [String] fully qualified name (e.g. "Foo::Bar")
    # @return [Hash, nil] declaration details or nil if not found
    def get_declaration(name)
      return nil unless indexed?

      decl = @graph[name]
      return nil unless decl

      declaration_to_hash(decl, detailed: true)
    rescue StandardError
      nil
    end

    # Get all declarations in the graph.
    #
    # @return [Array<Hash>] array of declaration summaries
    def all_declarations
      return [] unless indexed?

      @graph.declarations.map { |decl| declaration_to_hash(decl) }
    rescue StandardError
      []
    end

    # Get declarations defined in a specific file.
    #
    # @param path [String] relative or absolute file path
    # @return [Array<Hash>] declarations found in the file
    def file_declarations(path)
      return [] unless indexed?

      doc = @graph.documents.find { |d| d.uri.end_with?(path) || d.uri == path }
      return [] unless doc

      doc.definitions.map { |defn| definition_to_hash(defn) }
    rescue StandardError
      []
    end

    # Get descendants (subclasses/includers) of a declaration.
    #
    # @param name [String] fully qualified name
    # @return [Array<String>] descendant names
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
    def constant_references
      return [] unless indexed?

      @graph.constant_references.map do |ref|
        { name: ref.respond_to?(:name) ? ref.name : ref.to_s,
          location: ref.respond_to?(:location) ? format_location(ref.location) : nil }.compact
      end
    rescue StandardError
      []
    end

    # High-level codebase statistics from the rubydex index.
    #
    # @return [Hash] statistics about the indexed codebase
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
        total_methods: count_methods(declarations),
        total_constant_references: safe_count(@graph, :constant_references),
        total_method_references: safe_count(@graph, :method_references)
      }
    rescue StandardError
      {}
    end

    private

    # Collects all Ruby source files under the project root for indexing.
    #
    # @return [Array<String>] absolute file paths
    def ruby_source_files
      excluded = %w[node_modules tmp log vendor .git .bundle]
      Dir.glob(File.join(@root, '**', '*.rb')).reject do |path|
        excluded.any? { |dir| path.include?("/#{dir}/") }
      end
    end

    # Converts a rubydex declaration to a serializable hash.
    #
    # @param decl [Object] rubydex declaration
    # @param detailed [Boolean] whether to include full details
    # @return [Hash]
    def declaration_to_hash(decl, detailed: false)
      hash = {
        name: decl.name,
        unqualified_name: decl.respond_to?(:unqualified_name) ? decl.unqualified_name : nil,
        type: declaration_type(decl)
      }

      if detailed
        hash[:definitions] = decl.definitions.map { |d| definition_to_hash(d) } if decl.respond_to?(:definitions)
        hash[:ancestors] = decl.ancestors.map(&:name) if decl.respond_to?(:ancestors)
        hash[:descendants] = decl.descendants.map(&:name) if decl.respond_to?(:descendants)
        hash[:owner] = decl.owner.name if decl.respond_to?(:member) && decl.respond_to?(:owner) && decl.owner
      end

      hash.compact
    end

    # Converts a rubydex definition to a serializable hash.
    #
    # @param defn [Object] rubydex definition
    # @return [Hash]
    def definition_to_hash(defn)
      hash = { name: defn.name }
      hash[:location] = format_location(defn.location) if defn.respond_to?(:location)
      hash[:comments] = defn.comments if defn.respond_to?(:comments) && defn.comments.present?
      hash[:deprecated] = true if defn.respond_to?(:deprecated?) && defn.deprecated?
      hash.compact
    end

    # Formats a rubydex location into a readable string.
    #
    # @param location [Object] rubydex location object
    # @return [String, nil]
    def format_location(location)
      return nil unless location
      return location.to_s unless location.respond_to?(:path)

      path = location.path
      path = path.sub("#{@root}/", '') if path&.start_with?(@root)
      path
    end

    # Determines the type of a rubydex declaration.
    #
    # @param decl [Object] rubydex declaration
    # @return [String]
    def declaration_type(decl)
      klass = decl.class.name.to_s.split('::').last&.downcase
      case klass
      when /class/ then 'class'
      when /module/ then 'module'
      when /method/ then 'method'
      when /constant/ then 'constant'
      else 'declaration'
      end
    end

    def class_declaration?(decl)
      declaration_type(decl) == 'class'
    end

    def module_declaration?(decl)
      declaration_type(decl) == 'module'
    end

    def count_methods(declarations)
      declarations.sum do |decl|
        if decl.respond_to?(:definitions)
          decl.definitions.count do |d|
            d.name.to_s.include?('(') || declaration_type(d) == 'method'
          rescue StandardError
            false
          end
        else
          0
        end
      rescue StandardError
        0
      end
    end

    def safe_count(graph, method)
      return 0 unless graph.respond_to?(method)

      graph.send(method).count
    rescue StandardError
      0
    end
  end
end
