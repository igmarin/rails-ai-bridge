# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Maps an evidence source to a compact +[VERIFIED]+ / +[INFERRED]+ tag.
    #
    # Verified only when ActiveRecord reflection or rubydex/Prism agrees.
    # Source-regex extracts and static schema parses stay inferred.
    # Unknown sources under-claim as inferred — there is no third status.
    module ConfidenceTag
      VERIFIED = '[VERIFIED]'
      INFERRED = '[INFERRED]'

      VERIFIED_SOURCES = %i[reflection rubydex prism live].freeze

      module_function

      # @param source [Symbol, String, nil] evidence origin
      # @return [String] +[VERIFIED]+ or +[INFERRED]+
      def tag(source)
        return INFERRED if source.nil?

        VERIFIED_SOURCES.include?(source.to_sym) ? VERIFIED : INFERRED
      end

      # @param text [String] fact line without a tag
      # @param source [Symbol, String, nil] evidence origin
      # @return [String] +text+ with a trailing confidence tag
      def tagged(text, source)
        "#{text} #{tag(source)}"
      end

      # Summarizes how many facts came from each evidence source.
      #
      # @param counts [Hash] fact count per source, keyed by Symbol or String, in display order
      # @return [String, nil] e.g. +"Verification: [VERIFIED] reflection (3) · [INFERRED] regex (2)"+,
      #   or +nil+ when no source has a positive count
      def footer(counts)
        parts = counts.filter_map do |source, count|
          next unless count.to_i.positive?

          "#{tag(source)} #{source} (#{count})"
        end
        return if parts.empty?

        "Verification: #{parts.join(' · ')}"
      end
    end
  end
end
