# frozen_string_literal: true

require 'json'

module RailsAiBridge
  module Serializers
    class JsonSerializer
      attr_reader :context

      # @param context [Hash] the introspection context hash to serialize
      def initialize(context)
        @context = context
      end

      # Serializes the context hash to a pretty-printed JSON string.
      #
      # @return [String] pretty-printed JSON representation of the context
      def call
        JSON.pretty_generate(serializable_context)
      end

      private

      # @return [Hash] context plus the anti-hallucination rules array when enabled
      def serializable_context
        return context unless AntiHallucinationRules.enabled?

        context.merge(anti_hallucination_rules: AntiHallucinationRules.rules)
      end
    end
  end
end
