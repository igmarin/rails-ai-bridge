# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Dedicated semantic analysis introspector powered by rubydex.
    #
    # Analyzes the entire codebase to extract:
    # - Common implementation patterns
    # - Semantic relationships between code elements
    # - Complexity hotspots and frequently referenced areas
    # - Codebase statistics
    #
    # Returns an empty hash with an informational message when rubydex
    # is not available or not enabled.
    class SemanticIntrospector
      attr_reader :app

      # Maximum declarations to include in pattern detection to avoid huge payloads.
      MAX_PATTERN_DECLARATIONS = 200

      # Maximum complexity hotspots to return.
      MAX_HOTSPOTS = 20

      def initialize(app)
        @app = app
      end

      # Builds a semantic analysis hash for the Rails application.
      #
      # @return [Hash] semantic analysis results or error/info hash
      def call
        config = RailsAiBridge.configuration
        unless config.rubydex_available?
          return { info: 'Rubydex is not available. Install the rubydex gem and set ' \
                         'config.rubydex_enabled = true to enable semantic analysis.' }
        end

        adapter = RubydexAdapter.instance(app.root.to_s)

        {
          codebase_stats: adapter.codebase_stats,
          patterns: detect_patterns(adapter),
          relationships: analyze_relationships(adapter),
          complexity_hotspots: find_complexity_hotspots(adapter)
        }
      rescue StandardError => error
        Rails.logger.warn "[rails-ai-bridge] SemanticIntrospector failed: #{error.message}"
        { error: error.message }
      end

      private

      # Detects common implementation patterns across the codebase.
      #
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Hash] detected patterns
      def detect_patterns(adapter)
        declarations = adapter.all_declarations.first(MAX_PATTERN_DECLARATIONS)
        return {} if declarations.empty?

        classes = declarations.select { |d| d[:type] == 'class' }
        modules = declarations.select { |d| d[:type] == 'module' }

        {
          total_classes: classes.size,
          total_modules: modules.size,
          namespace_distribution: namespace_distribution(declarations),
          common_patterns: detect_code_patterns(classes, adapter)
        }
      end

      # Analyzes semantic relationships between code elements.
      #
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Hash] relationship analysis
      def analyze_relationships(adapter)
        declarations = adapter.all_declarations.first(MAX_PATTERN_DECLARATIONS)
        return {} if declarations.empty?

        classes = declarations.select { |d| d[:type] == 'class' }
        inheritance_tree = build_inheritance_tree(classes, adapter)

        {
          inheritance_tree: inheritance_tree,
          most_extended: find_most_extended(classes, adapter),
          orphan_classes: find_orphan_classes(classes, adapter)
        }
      end

      # Finds code areas with highest complexity based on definition count and relationships.
      #
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Array<Hash>] complexity hotspots sorted by score
      def find_complexity_hotspots(adapter)
        declarations = adapter.all_declarations
        return [] if declarations.empty?

        hotspots = declarations.filter_map do |decl|
          detail = adapter.get_declaration(decl[:name])
          next unless detail

          score = calculate_hotspot_score(detail)
          next if score < 5

          {
            name: decl[:name],
            type: decl[:type],
            complexity_score: score,
            definitions_count: detail[:definitions]&.size || 0,
            ancestors_count: detail[:ancestors]&.size || 0,
            descendants_count: detail[:descendants]&.size || 0
          }
        end

        hotspots.sort_by { |h| -h[:complexity_score] }.first(MAX_HOTSPOTS)
      end

      # Calculates a complexity score for a declaration.
      #
      # @param detail [Hash] declaration details from rubydex
      # @return [Integer] complexity score
      def calculate_hotspot_score(detail)
        score = 0
        score += (detail[:definitions]&.size || 0) * 2
        score += detail[:ancestors]&.size || 0
        score += (detail[:descendants]&.size || 0) * 3
        score
      end

      # Analyzes namespace distribution across declarations.
      #
      # @param declarations [Array<Hash>] declaration list
      # @return [Hash{String => Integer}] namespace to count mapping
      def namespace_distribution(declarations)
        declarations
          .map { |d| d[:name].to_s.split('::').first }
          .compact
          .reject(&:empty?)
          .tally
          .sort_by { |_, count| -count }
          .first(15)
          .to_h
      end

      # Detects common code patterns from class declarations.
      #
      # @param classes [Array<Hash>] class declarations
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Array<String>] detected pattern names
      def detect_code_patterns(classes, adapter)
        patterns = []

        class_names = classes.pluck(:name)
        patterns << 'service_objects' if class_names.any? { |n| n.to_s.end_with?('Service') }
        patterns << 'form_objects' if class_names.any? { |n| n.to_s.end_with?('Form') }
        patterns << 'query_objects' if class_names.any? { |n| n.to_s.end_with?('Query') }
        patterns << 'presenters' if class_names.any? { |n| n.to_s.end_with?('Presenter', 'Decorator') }
        patterns << 'serializers' if class_names.any? { |n| n.to_s.end_with?('Serializer') }
        patterns << 'policies' if class_names.any? { |n| n.to_s.end_with?('Policy') }
        patterns << 'validators' if class_names.any? { |n| n.to_s.end_with?('Validator') }
        patterns << 'observers' if class_names.any? { |n| n.to_s.end_with?('Observer') }
        patterns << 'interactors' if class_names.any? { |n| n.to_s.end_with?('Interactor') }
        patterns << 'commands' if class_names.any? { |n| n.to_s.end_with?('Command') }
        patterns << 'jobs' if class_names.any? { |n| n.to_s.end_with?('Job') }
        patterns << 'mailers' if class_names.any? { |n| n.to_s.end_with?('Mailer') }

        # Check for concerns usage
        concern_count = adapter.all_declarations.count { |d| d[:type] == 'module' && d[:name].to_s.include?('Concern') }
        patterns << "concerns(#{concern_count})" if concern_count.positive?

        patterns
      end

      # Builds a simplified inheritance tree from class declarations.
      #
      # @param classes [Array<Hash>] class declarations
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Hash{String => Array<String>}] parent to children mapping
      def build_inheritance_tree(classes, adapter)
        tree = {}
        classes.each do |klass|
          descendants = adapter.descendants(klass[:name])
          tree[klass[:name]] = descendants if descendants.any?
        end
        tree.sort_by { |_, children| -children.size }.first(15).to_h
      end

      # Finds classes with the most descendants (most extended/inherited).
      #
      # @param classes [Array<Hash>] class declarations
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Array<Hash>] sorted by descendant count
      def find_most_extended(classes, adapter)
        extended = classes.filter_map do |klass|
          descendants = adapter.descendants(klass[:name])
          next if descendants.empty?

          { name: klass[:name], descendants_count: descendants.size }
        end

        extended.sort_by { |h| -h[:descendants_count] }.first(10)
      end

      # Finds classes with no descendants (leaf classes).
      #
      # @param classes [Array<Hash>] class declarations
      # @param adapter [RubydexAdapter] initialized rubydex adapter
      # @return [Integer] count of orphan classes
      def find_orphan_classes(classes, adapter)
        classes.count do |klass|
          adapter.descendants(klass[:name]).empty? && adapter.ancestors(klass[:name]).size <= 1
        end
      end
    end
  end
end
