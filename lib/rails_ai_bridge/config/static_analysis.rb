# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds static analysis settings for confidence tags and the optional Prism pass.
    #
    # Confidence tags mark each fact as [VERIFIED] or [INFERRED]. The Prism pass is
    # off by default. It needs the +prism+ gem, which this gem does not depend on.
    #
    # @see RailsAiBridge::Tools::ConfidenceTag
    class StaticAnalysis
      # @return [Boolean] whether tool output carries [VERIFIED] / [INFERRED] tags
      attr_accessor :confidence_tags_enabled

      # @return [Boolean] whether the optional Prism AST pass runs
      attr_accessor :prism_enabled

      # @return [Integer] maximum number of source files the Prism pass scans
      attr_accessor :prism_max_files

      def initialize
        @confidence_tags_enabled = true
        @prism_enabled = false
        @prism_max_files = 500
      end
    end
  end
end
