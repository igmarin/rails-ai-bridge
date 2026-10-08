# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Optional Prism AST pass that finds controller filter macros in source files.
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

        walk(result.value).select { |node| filter_macro?(node) }.flat_map { |node| filter_facts(node, path) }
      end

      # Every node in the tree, depth-first, starting with +node+. Method bodies are
      # skipped: a filter macro only registers when it runs in a class or included block.
      def walk(node)
        return [] unless node

        children = node.compact_child_nodes.grep_v(Prism::DefNode)
        [node, *children.flat_map { |child| walk(child) }]
      end

      # :reek:UtilityFunction -- a pure predicate on the node; the macro list is a constant
      def filter_macro?(node)
        node.is_a?(Prism::CallNode) && !node.receiver && FILTER_MACROS.include?(node.name)
      end

      # :reek:FeatureEnvy -- builds facts from the macro node it is given
      def filter_facts(node, path)
        Array(node.arguments&.arguments).grep(Prism::SymbolNode).map do |symbol|
          {
            kind: node.name,
            name: symbol.unescaped,
            file: path,
            line: node.location.start_line,
            provenance: :prism
          }
        end
      end
    end
  end
end
