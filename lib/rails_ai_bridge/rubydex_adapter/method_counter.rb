# frozen_string_literal: true

module RailsAiBridge
  class RubydexAdapter
    # Counts method-like definitions across rubydex declarations.
    #
    # Replaces the nested conditional counting in the adapter with a flat,
    # testable pipeline. A definition is considered a method when its name
    # includes parentheses or it is classified as a method type by the
    # serializer.
    class MethodCounter
      # @param serializer [Serializer] for declaration_type classification
      def initialize(serializer:)
        @serializer = serializer
      end

      # Counts method definitions across declarations.
      #
      # @param declarations [Array<Object>] rubydex declaration objects
      # @return [Integer] total method count
      # @raise [StandardError] rescued internally, returns 0
      def count(declarations)
        declarations.sum { |decl| method_count_for(decl) }
      rescue StandardError
        0
      end

      private

      def method_count_for(decl)
        return 0 unless decl.respond_to?(:definitions)

        decl.definitions.count { |d| method_like?(d) }
      rescue StandardError
        0
      end

      def method_like?(defn)
        defn.name.to_s.include?('(') || @serializer.declaration_type(defn) == 'method'
      rescue StandardError
        false
      end
    end
  end
end
