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
        JSON.pretty_generate(context)
      end
    end
  end
end
