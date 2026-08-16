# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ControllerIntrospector
      # Extracts before/after/around filter metadata from an ActionController class.
      #
      # Walks the controller and its ancestors' +_process_action_callbacks+ chains
      # so inherited +before_action+ / +after_action+ filters (e.g. parent auth)
      # are attributed to the class that defined them. Filters whose +:only+ /
      # +:except+ conditions match none of the controller's actions are omitted.
      class FilterExtractor
        FRAMEWORK_PREFIXES = %w[ActionController:: AbstractController:: ActionDispatch::].freeze

        # @param controller [Class] ActionController class to inspect
        def initialize(controller)
          @controller = controller
        end

        # @return [Array<Hash>] list of filter descriptors
        def call
          effective_callbacks.filter_map { |cb| build_filter(cb) if valid_filter?(cb) }
                             .select { |filter| applicable?(filter) }
        rescue StandardError
          []
        end

        private

        def build_filter(callback)
          filter = { name: callback.filter.to_s, kind: callback.kind.to_s }
          source = source_class_name(callback)
          filter[:source] = source if source
          append_conditions(filter, callback)
          filter
        end

        def valid_filter?(callback)
          filter = callback.filter
          !(filter.is_a?(Proc) || filter.to_s.start_with?('_'))
        end

        # Child chains already include inherited callbacks and honor
        # +skip_before_action+. Ancestor chains are still walked so a
        # subclass that only exposes its own callbacks still surfaces parent
        # filters, and so each callback can be attributed to its owner.
        def effective_callbacks
          seen = {}
          controller_lineage.flat_map { |klass| Array(safe_callbacks(klass)) }
                            .select do |callback|
            key = callback_key(callback)
            next false if seen[key]

            seen[key] = true
            included_in_effective_chain?(callback)
          end
        end

        def included_in_effective_chain?(callback)
          child_chain = safe_callbacks(@controller)
          return true if child_chain.empty?

          child_chain.include?(callback) || !inherited_into_child_chain?
        end

        def inherited_into_child_chain?
          parent = @controller.is_a?(Class) ? @controller.superclass : nil
          return false unless parent.respond_to?(:_process_action_callbacks)

          parent_chain = safe_callbacks(parent)
          return false if parent_chain.empty?

          safe_callbacks(@controller).intersect?(parent_chain)
        end

        def source_class_name(callback)
          owner = controller_lineage.find { |klass| own_callback?(klass, callback) }
          return unless owner.is_a?(Class)
          return if framework_controller?(owner)

          owner.name
        end

        def own_callback?(klass, callback)
          chain = safe_callbacks(klass)
          parent = klass.is_a?(Class) ? klass.superclass : nil
          own = if parent.respond_to?(:_process_action_callbacks)
                  chain - safe_callbacks(parent)
                else
                  chain
                end
          own.include?(callback)
        end

        def controller_lineage
          return [@controller] unless @controller.is_a?(Class) && @controller.respond_to?(:ancestors)

          @controller.ancestors.select do |mod|
            mod.is_a?(Class) && mod.respond_to?(:_process_action_callbacks)
          end
        end

        def framework_controller?(klass)
          name = klass.name
          return true if name.nil?

          FRAMEWORK_PREFIXES.any? { |prefix| name.start_with?(prefix) }
        end

        def safe_callbacks(klass)
          Array(klass._process_action_callbacks)
        rescue StandardError
          []
        end

        def callback_key(callback)
          [callback.object_id, callback.filter.to_s, callback.kind.to_s]
        end

        def applicable?(filter)
          actions = controller_actions
          return true if actions.empty?

          if filter[:only]
            filter[:only].intersect?(actions)
          elsif filter[:except]
            (actions - filter[:except]).any?
          else
            true
          end
        end

        def controller_actions
          return [] unless @controller.respond_to?(:action_methods)

          Array(@controller.action_methods).map(&:to_s)
        rescue StandardError
          []
        end

        # Accesses @if/@unless ivars directly — this is Rails private API
        # (ActiveSupport::Callbacks::Callback). No public accessor exists.
        # Rails 7.1+ stores only/except as ActionFilter objects with @actions.
        # If Rails changes internal representation, this degrades gracefully
        # via the rescue StandardError in #call.
        def append_conditions(filter, callback)
          only = extract_action_conditions(callback.instance_variable_get(:@if))
          except = extract_action_conditions(callback.instance_variable_get(:@unless))
          filter[:only] = only if only.any?
          filter[:except] = except if except.any?
        end

        def extract_action_conditions(conditions)
          return [] unless conditions

          conditions.filter_map { |condition| parse_action_condition(condition) }.flatten
        end

        def parse_action_condition(condition)
          actions = action_filter_actions(condition)
          return actions if actions

          match = condition.to_s.match(/action_name\s*==\s*['"](\w+)['"]/)
          match ? [match[1]] : nil
        end

        def action_filter_actions(condition)
          return unless condition.instance_variable_defined?(:@actions)

          Array(condition.instance_variable_get(:@actions)).map(&:to_s)
        end
      end
    end
  end
end
