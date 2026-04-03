# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Base class for all MarkdownSerializer section and provider formatters.
      # Subclasses implement {#call} to return a markdown string or nil.
      class Base
        attr_reader :context

        # @param context [Hash] introspection payload (symbol keys) passed from serializers
        # @return [void]
        def initialize(context)
          @context = context
        end

        # @return [String, nil]
        def call
          raise NotImplementedError, "#{self.class}#call is not implemented"
        end
      end
    end
  end
end
