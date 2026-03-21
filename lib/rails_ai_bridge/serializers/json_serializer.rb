# frozen_string_literal: true

require "json"

module RailsAiBridge
  module Serializers
    class JsonSerializer
      attr_reader :context

      def initialize(context)
        @context = context
      end

      def call
        JSON.pretty_generate(context)
      end
    end
  end
end
