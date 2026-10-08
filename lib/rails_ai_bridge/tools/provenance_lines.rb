# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Renders confidence tags into tool output when +confidence_tags_enabled+ is on.
    #
    # With tags off, every method returns its input unchanged, so tool output stays
    # byte-identical to output rendered before tags existed.
    class ProvenanceLines
      # @param enabled [Boolean] whether tags are rendered
      def initialize(enabled)
        @enabled = enabled
      end

      # @param text [String] fact line without a tag
      # @param provenance [Symbol, nil] evidence origin of the fact
      # @return [String] +text+ with a trailing tag when enabled
      def tag(text, provenance)
        return text unless @enabled

        ConfidenceTag.tagged(text, provenance)
      end

      # @param provenances [Array<Symbol, nil>] provenance of each rendered fact
      # @return [String, nil] verification summary line, or +nil+ when disabled or empty
      def footer(provenances)
        return unless @enabled

        ConfidenceTag.footer(provenances.map { |source| source || :heuristic }.tally)
      end
    end
  end
end
