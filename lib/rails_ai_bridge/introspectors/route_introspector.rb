# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts route information from the Rails router including
    # HTTP verb, path, controller#action, declared URL helper, required params,
    # and route constraints.
    class RouteIntrospector
      attr_reader :app, :config

      def initialize(app)
        @app = app
        @config = RailsAiBridge.configuration
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

          parsed = RouteParser.new(route).to_h
          next if excluded_route?(parsed)

          parsed
        end
      end

      # @param route [Hash]
      # @return [Boolean]
      def excluded_route?(route)
        tokens = [
          route[:controller],
          route[:controller].to_s.split('/').last,
          route[:name]
        ]
        tokens.concat(route_path_tokens(route[:path]))
        tokens.compact.any? { |token| ExclusionHelper.excluded_class_or_table?(token, config) }
      end

      # @param path [String, nil]
      # @return [Array<String>]
      def route_path_tokens(path)
        path.to_s.split('/').reject { |segment| segment.empty? || segment.start_with?(':', '(') }
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
            helper: path_helper,
            required_params: required_params,
            constraints: extract_constraints
          }.compact
        end

        private

        # Rails path helper from the route's declared name only (`post` → `post_path`).
        # Unnamed routes have no name, so no helper is invented from the path string.
        #
        # @return [String, nil]
        def path_helper
          name = @route.name
          return if name.blank?

          "#{name}_path"
        end

        # Required dynamic segments from Journey (`required_parts` / `required_names`).
        #
        # @return [Array<String>, nil]
        def required_params
          names = required_part_names
          names.presence
        end

        # @return [Array<String>]
        def required_part_names
          if @route.respond_to?(:required_parts)
            Array(@route.required_parts).map(&:to_s)
          elsif @route.path.respond_to?(:required_names)
            Array(@route.path.required_names).map(&:to_s)
          else
            []
          end
        end

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
            name: @route[:name],
            helper: @route[:helper],
            required_params: @route[:required_params]
          }.compact
        end
      end
    end
  end
end
