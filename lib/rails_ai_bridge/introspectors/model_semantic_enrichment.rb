# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Mixin that adds rubydex-powered semantic analysis helpers
    # to {ModelIntrospector}. Extracted to keep the main class
    # within the Metrics/ClassLength budget.
    module ModelSemanticEnrichment
      private

      # Extracts semantic analysis data from rubydex when available.
      #
      # @param model [Class] ActiveRecord model class
      # @return [Hash] semantic data including summary, similar models, and complexity
      def extract_semantic_data(model)
        return {} unless config.rubydex_available?

        data = {}
        data[:semantic_summary] = extract_semantic_summary(model)
        data[:similar_models] = find_similar_models(model)
        data[:complexity_score] = calculate_complexity_score(model)
        data.compact
      end

      # Generates a semantic summary of the model from rubydex analysis.
      #
      # @param model [Class] ActiveRecord model class
      # @return [String, nil] human-readable summary
      def extract_semantic_summary(model)
        adapter = RubydexAdapter.instance
        decl = adapter.get_declaration(model.name)
        return nil unless decl

        parts = []
        parts << "#{decl[:type]} with #{decl[:definitions]&.size || 0} definitions"
        parts << "inherits from #{decl[:ancestors]&.first}" if decl[:ancestors]&.any?
        parts << "#{decl[:descendants]&.size} subclasses" if decl[:descendants]&.any?
        parts.join(', ')
      rescue StandardError
        nil
      end

      # Finds semantically similar models using rubydex ancestor/descendant relationships.
      #
      # @param model [Class] ActiveRecord model class
      # @return [Array<String>, nil] names of similar models
      def find_similar_models(model)
        adapter = RubydexAdapter.instance
        related = Set.new

        model_ancestors = adapter.ancestors(model.name)
        model_ancestors.each do |ancestor|
          descendants = adapter.descendants(ancestor)
          descendants.each { |d| related.add(d) }
        end

        adapter.descendants(model.name).each { |d| related.add(d) }

        related.delete(model.name)
        result = related.to_a.sort.first(10)
        result.empty? ? nil : result
      rescue StandardError
        nil
      end

      # Calculates a complexity score for the model based on rubydex analysis.
      #
      # Score is derived from: number of definitions, ancestors, and descendants.
      #
      # @param model [Class] ActiveRecord model class
      # @return [Integer, nil] complexity score (higher = more complex)
      def calculate_complexity_score(model)
        adapter = RubydexAdapter.instance
        decl = adapter.get_declaration(model.name)
        return nil unless decl

        score = 0
        score += (decl[:definitions]&.size || 0) * 2
        score += decl[:ancestors]&.size || 0
        score += (decl[:descendants]&.size || 0) * 3
        score
      rescue StandardError
        nil
      end
    end
  end
end
