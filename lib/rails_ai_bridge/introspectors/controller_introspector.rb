# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers controllers and extracts filters, strong params,
    # respond_to formats, concerns, actions, and API detection.
    class ControllerIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        eager_load_controllers!
        controllers = discover_controllers

        result = controllers.each_with_object({}) do |ctrl, hash|
          hash[ctrl.name] = extract_controller_details(ctrl)
        rescue StandardError => e
          hash[ctrl.name] = { error: e.message }
        end

        { controllers: result }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def eager_load_controllers!
        Rails.application.eager_load! unless Rails.application.config.eager_load
      rescue StandardError
        nil
      end

      def discover_controllers
        return [] unless defined?(ActionController::Base)

        bases = [ActionController::Base]
        bases << ActionController::API if defined?(ActionController::API)

        bases.flat_map(&:descendants).reject do |ctrl|
          ctrl.name.nil? || ctrl.name == 'ApplicationController' ||
            ctrl.name.start_with?('Rails::', 'ActionMailbox::', 'ActiveStorage::')
        end.uniq.sort_by(&:name)
      end

      def extract_controller_details(ctrl)
        source = read_source(ctrl)

        {
          parent_class: ctrl.superclass.name,
          api_controller: api_controller?(ctrl),
          actions: extract_actions(ctrl),
          filters: extract_filters(ctrl),
          concerns: extract_concerns(ctrl),
          strong_params: extract_strong_params(source),
          respond_to_formats: extract_respond_to(source)
        }.compact
      end

      def api_controller?(ctrl)
        return true if defined?(ActionController::API) && ctrl.ancestors.include?(ActionController::API)

        false
      end

      def extract_actions(ctrl)
        ctrl.action_methods.to_a.sort
      rescue StandardError
        []
      end

      def extract_filters(ctrl)
        return [] unless ctrl.respond_to?(:_process_action_callbacks)

        ctrl._process_action_callbacks.filter_map do |cb|
          next if cb.filter.is_a?(Proc) || cb.filter.to_s.start_with?('_')

          filter = { name: cb.filter.to_s, kind: cb.kind.to_s }
          filter[:only] = cb.instance_variable_get(:@if)&.filter_map { |c| extract_action_condition(c) }&.flatten
          filter[:except] = cb.instance_variable_get(:@unless)&.filter_map { |c| extract_action_condition(c) }&.flatten
          filter.delete(:only) if filter[:only] && filter[:only].empty?
          filter.delete(:except) if filter[:except] && filter[:except].empty?
          filter
        end
      rescue StandardError
        []
      end

      def extract_action_condition(condition)
        return nil unless condition.is_a?(String) || condition.respond_to?(:to_s)

        match = condition.to_s.match(/action_name\s*==\s*['"](\w+)['"]/)
        match ? [match[1]] : nil
      end

      def extract_concerns(ctrl)
        ctrl.ancestors
            .select { |mod| mod.is_a?(Module) && !mod.is_a?(Class) }
            .reject do |mod|
          mod.name&.start_with?('ActionController', 'ActionDispatch', 'ActiveSupport',
                                'AbstractController')
        end
          .map(&:name)
          .compact
      rescue StandardError
        []
      end

      def extract_strong_params(source)
        return [] if source.nil?

        source.scan(/def\s+(\w+_params)\b/).flatten.uniq
      end

      def extract_respond_to(source)
        return [] if source.nil?
        return [] unless source.match?(/respond_to\s+do/)

        source.scan(/format\.(\w+)/).flatten.uniq.sort
      end

      def read_source(ctrl)
        path = source_path(ctrl)
        return nil unless path && File.exist?(path)

        File.read(path)
      rescue StandardError
        nil
      end

      def source_path(ctrl)
        root = app.root.to_s
        underscored = ctrl.name.underscore
        File.join(root, 'app', 'controllers', "#{underscored}.rb")
      end
    end
  end
end
