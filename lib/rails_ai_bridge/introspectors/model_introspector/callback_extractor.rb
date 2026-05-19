# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ModelIntrospector
      # Extracts callback metadata from an ActiveRecord model.
      #
      # Iterates over standard ActiveRecord callback types (before/after
      # validation, save, create, update, destroy, commit, rollback) and
      # collects named callback filters, excluding framework-generated
      # entries and Proc-based callbacks.
      class CallbackExtractor
        CALLBACK_TYPES = %i[
          before_validation after_validation
          before_save after_save
          before_create after_create
          before_update after_update
          before_destroy after_destroy
          after_commit after_rollback
        ].freeze

        # @param model [Class] ActiveRecord model class
        # @param excluded_prefixes [Array<String>] callback name prefixes to skip
        def initialize(model, excluded_prefixes:)
          @model = model
          @excluded_prefixes = excluded_prefixes
        end

        # @return [Hash<String, Array<String>>] callbacks grouped by type
        def call
          CALLBACK_TYPES.each_with_object({}) do |type, hash|
            names = callback_names_for(type)
            hash[type.to_s] = names unless names.empty?
          end
        rescue StandardError
          {}
        end

        private

        attr_reader :model, :excluded_prefixes

        # Uses send because _*_callbacks are private ActiveRecord internals.
        # Safety: `type` is always from the frozen CALLBACK_TYPES constant.
        def callback_names_for(type)
          model.send(:"_#{type}_callbacks")
               .map(&:filter)
               .reject { |filter| filter.is_a?(Proc) || filter.to_s.start_with?(*excluded_prefixes) }
               .map(&:to_s)
        end
      end
    end
  end
end
