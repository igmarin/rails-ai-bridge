# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Optional Prism AST pass that finds controller filter macros and instance method
    # definitions in source files.
    #
    # Facts found this way carry +provenance: :prism+, so the tools layer can
    # render them as +[VERIFIED]+. Prism is not a gem dependency. When it cannot
    # be loaded, or the scan fails, +facts_for+ returns an error hash and never raises.
    class StaticPrismScanner
      # Controller macros whose symbol arguments name filters.
      FILTER_MACROS = %i[
        before_action after_action around_action
        skip_before_action skip_after_action skip_around_action
      ].freeze

      # Prism node classes, by short name, mapped to the role each plays in the walk. Names are
      # strings so this file does not reference Prism when it loads.
      NODE_ROLES = {
        'ClassNode' => :class,
        'ModuleNode' => :module,
        'SingletonClassNode' => :singleton,
        'BlockNode' => :block,
        'DefNode' => :def,
        'CallNode' => :call
      }.freeze

      # Scopes whose name becomes part of the owner of the methods inside them.
      NAMESPACE_ROLES = %i[class module].freeze

      # @param max_files [Integer] maximum number of files this scanner reads
      # @param loader [#call] loads the prism library and raises LoadError when it is unavailable
      def initialize(max_files:, loader: -> { require 'prism' })
        @max_files = max_files
        @files_read = 0
        @prism_available = begin
          loader.call
          true
        rescue LoadError
          false
        end
      end

      # @param path [String] source file to scan
      # @return [Hash] +{ facts: [...] }+ on success, or +{ error: String }+ when Prism is
      #   unavailable, the file limit is reached, or the file cannot be read or parsed
      def facts_for(path)
        blocked_reason = scan_blocked_reason
        return { error: blocked_reason } if blocked_reason

        scan(path)
      rescue StandardError => error
        { error: "prism scan failed: #{error.message}" }
      end

      private

      def scan_blocked_reason
        return 'prism is not available' unless @prism_available
        return "prism_max_files (#{@max_files}) reached" if @files_read >= @max_files

        nil
      end

      def scan(path)
        @files_read += 1
        { facts: extract_facts(path) }
      end

      def extract_facts(path)
        result = Prism.parse(File.read(path))
        raise ArgumentError, 'file has syntax errors' unless result.success?

        root = result.value
        (filter_facts_in(root) + method_facts(root)).map { |fact| fact.merge(file: path) }
      end

      # Filter macros in the tree. Method bodies are skipped: a filter macro only registers when
      # it runs in a class or included block.
      def filter_facts_in(root)
        walk(root).select { |node| filter_macro?(node) }.flat_map { |node| filter_facts(node) }
      end

      # Every node in the tree, depth-first, starting with +node+, without method bodies.
      def walk(node)
        children = node.compact_child_nodes.grep_v(Prism::DefNode)
        [node, *children.flat_map { |child| walk(child) }]
      end

      # Instance method definitions, each tagged with the class or module that owns it. A
      # method counts only when its direct enclosing scope is a class body, so a same-named
      # method in a nested class, in +class << self+, or in a block is never reported for
      # the outer class.
      def method_facts(node, scope = [])
        role = NODE_ROLES[node.class.name.demodulize]
        return instance_method_facts(node, scope) if role == :def

        inner = scope + [scope_entry(role, node)].compact
        node.compact_child_nodes.flat_map { |child| method_facts(child, inner) }
      end

      # The scope a node opens for the definitions inside it, or nil when it opens none.
      # :reek:UtilityFunction -- a pure mapping from the node's role to the scope it opens
      def scope_entry(role, node)
        case role
        when :class, :module then [role, node.constant_path.slice]
        when :singleton, :block then [role, nil]
        end
      end

      # :reek:FeatureEnvy -- builds the fact from the method node it is given
      # :reek:UtilityFunction -- a pure builder over the node and its scope
      def instance_method_facts(node, scope)
        return [] if node.receiver || scope.last&.first != :class

        owner = scope.filter_map { |kind, name| name if NAMESPACE_ROLES.include?(kind) }.join('::')
        [{ kind: :def, name: node.name.to_s, owner: owner, line: node.location.start_line, provenance: :prism }]
      end

      # :reek:UtilityFunction -- a pure predicate on the node; the macro list is a constant
      def filter_macro?(node)
        NODE_ROLES[node.class.name.demodulize] == :call && !node.receiver && FILTER_MACROS.include?(node.name)
      end

      # :reek:FeatureEnvy -- builds facts from the macro node it is given
      def filter_facts(node)
        Array(node.arguments&.arguments).grep(Prism::SymbolNode).map do |symbol|
          { kind: node.name, name: symbol.unescaped, line: node.location.start_line, provenance: :prism }
        end
      end
    end
  end
end
