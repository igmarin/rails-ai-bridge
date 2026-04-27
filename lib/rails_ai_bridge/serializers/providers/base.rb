# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Base class for all provider formatters.
      # Provides common context access and a consistent interface.
      class Base
        attr_reader :context

        # @param context [Hash] The introspection context.
        def initialize(context:)
          @context = context
        end
      end
    end
  end
end
