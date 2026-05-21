# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds rubydex semantic analysis configuration settings.
    #
    # Rubydex is an optional dependency providing static semantic analysis
    # of Ruby codebases via Shopify's rubydex toolkit.
    class Rubydex
      # @return [Boolean] whether rubydex integration is enabled
      attr_accessor :rubydex_enabled

      # @return [String] path to store the rubydex index (relative to Rails.root)
      attr_accessor :rubydex_index_path

      # @return [Boolean] whether the semantic introspector is enabled
      attr_accessor :semantic_introspector_enabled

      # @return [Symbol] depth of semantic context in generated files (:summary, :standard, :full)
      attr_accessor :semantic_context_depth

      # @return [Float] ratio of changed files that triggers a full rebuild (0.0–1.0)
      attr_accessor :rubydex_incremental_threshold

      # @return [Boolean] whether to persist file mtimes across process restarts
      attr_accessor :rubydex_persist_index

      def initialize
        @rubydex_enabled = false
        @rubydex_index_path = 'tmp/rubydex_index'
        @semantic_introspector_enabled = false
        @semantic_context_depth = :standard
        @rubydex_incremental_threshold = 0.3
        @rubydex_persist_index = false
      end
    end
  end
end
