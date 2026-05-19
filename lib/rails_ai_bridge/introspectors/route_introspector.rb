# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts route information from the Rails router including
    # HTTP verb, path, controller#action, and route constraints.
    class RouteIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      # @return [Hash] routes grouped by controller
      def call
        routes = extract_routes

        RouteCollection.new(routes).to_h.merge(
          mounted_engines: detect_mounted_engines
        )
      end

      private

      def extract_routes
        app.routes.routes.filter_map do |route|
          next if route.respond_to?(:internal?) && route.internal?
          next if route.defaults[:controller].blank?

          RouteParser.new(route).to_h
        end
      end

      def detect_mounted_engines
        app.routes.routes
           .select { |route| route.app.respond_to?(:app) && route.app.app.is_a?(Class) }
           .filter_map do |route|
             engine_class = route.app.app
             next unless engine_class < Rails::Engine

             {
               engine: engine_class.name,
               path: route.path.spec.to_s
             }
           rescue StandardError
             nil
           end
      end

      # Formats a single ActionDispatch route
      class RouteParser
        def initialize(route)
          @route = route
        end

        def to_h
          defaults = @route.defaults
          {
            verb: @route.verb.presence || 'ANY',
            path: @route.path.spec.to_s.gsub('(.:format)', ''),
            controller: defaults[:controller],
            action: defaults[:action],
            name: @route.name,
            constraints: extract_constraints
          }.compact
        end

        private

        def extract_constraints
          constraints = @route.constraints.to_s
          constraints.empty? ? nil : constraints
        rescue StandardError
          nil
        end
      end

      # Formats and groups a collection of parsed routes
      class RouteCollection
        def initialize(routes)
          @routes = routes
        end

        def to_h
          {
            total_routes: @routes.size,
            by_controller: group_by_controller,
            api_namespaces: detect_api_namespaces
          }
        end

        private

        def group_by_controller
          grouped = @routes.group_by { |route| route[:controller] }
          grouped.transform_values { |group| RoutePresenter.present_collection(group) }
        end

        def detect_api_namespaces
          @routes.filter_map do |route|
            match = route[:path].match(%r{(/api/v?\d*)})
            match&.captures&.first
          end.uniq
        end
      end

      # Presents a summarized route
      class RoutePresenter
        def self.present_collection(routes)
          routes.map { |route| new(route).to_h }
        end

        def initialize(route)
          @route = route
        end

        def to_h
          {
            verb: @route[:verb],
            path: @route[:path],
            action: @route[:action],
            name: @route[:name]
          }.compact
        end
      end
    end
  end
end
