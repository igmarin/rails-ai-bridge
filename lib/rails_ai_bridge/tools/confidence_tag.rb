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
    end
  end
end
