# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ControllerIntrospector
      # Extracts before/after/around filter metadata from an ActionController class.
      #
      # Iterates over the controller's +_process_action_callbacks+ and builds
      # a list of named filters with their kind (before, after, around) and
      # any :only / :except action conditions.
      class FilterExtractor
        # @param controller [Class] ActionController class to inspect
        def initialize(controller)
          @controller = controller
        end

        # @return [Array<Hash>] list of filter descriptors
        def call
          callbacks = @controller._process_action_callbacks
          extractor_class = self.class
          callbacks.filter_map { |cb| extractor_class.build_filter(cb) if extractor_class.valid_filter?(cb) }
        rescue StandardError
          []
        end

        def self.build_filter(callback)
          filter = { name: callback.filter.to_s, kind: callback.kind.to_s }
          append_conditions(filter, callback)
          filter
        end

        def self.valid_filter?(callback)
          filter = callback.filter
          !(filter.is_a?(Proc) || filter.to_s.start_with?('_'))
        end

        def self.append_conditions(filter, callback)
          only = extract_action_conditions(callback.instance_variable_get(:@if))
          except = extract_action_conditions(callback.instance_variable_get(:@unless))
          filter[:only] = only if only.any?
          filter[:except] = except if except.any?
        end

        def self.extract_action_conditions(conditions)
          return [] unless conditions

          conditions.filter_map { |condition| parse_action_condition(condition) }.flatten
        end

        def self.parse_action_condition(condition)
          match = condition.to_s.match(/action_name\s*==\s*['"](\w+)['"]/)
          match ? [match[1]] : nil
        end
      end
    end
  end
end
