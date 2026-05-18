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

        {
          total_routes: routes.size,
          by_controller: group_by_controller(routes),
          api_namespaces: detect_api_namespaces(routes),
          mounted_engines: detect_mounted_engines
        }
      end

      private

      def extract_routes
        app.routes.routes.filter_map do |route|
          next if route.respond_to?(:internal?) && route.internal?
          next if route.defaults[:controller].blank?

          {
            verb: route.verb.presence || 'ANY',
            path: route.path.spec.to_s.gsub('(.:format)', ''),
            controller: route.defaults[:controller],
            action: route.defaults[:action],
            name: route.name,
            constraints: extract_constraints(route)
          }.compact
        end
      end

      def extract_constraints(route)
        constraints = route.constraints.to_s
        constraints.empty? ? nil : constraints
      rescue StandardError
        nil
      end

      def group_by_controller(routes)
        routes.group_by { |route| route[:controller] }
              .transform_values { |group| group.map { |route| route_summary(route) } }
      end

      def route_summary(route)
        { verb: route[:verb], path: route[:path], action: route[:action], name: route[:name] }.compact
      end

      def detect_api_namespaces(routes)
        routes
          .select { |route| route[:path].match?(%r{/api/}) }
          .map { |route| route[:path].match(%r{(/api/v?\d*)})&.captures&.first }
          .compact
          .uniq
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
    end
  end
end
