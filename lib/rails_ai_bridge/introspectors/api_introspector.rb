# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers API layer setup: api_only mode, serializers, GraphQL,
    # versioning patterns, rate limiting.
    class ApiIntrospector
      attr_reader :app, :path_resolver

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      # Builds a read-only summary of API-oriented framework signals.
      #
      # @return [Hash] API-only flag, serializer, GraphQL, versioning, and rate-limit metadata
      def call
        {
          api_only: app.config.api_only,
          serializers: detect_serializers,
          graphql: detect_graphql,
          api_versioning: detect_versioning,
          rate_limiting: detect_rate_limiting
        }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def root
        app.root.to_s
      end

      def detect_serializers
        result = {}

        jbuilder_files = path_resolver.glob_for('app/views', '**/*.jbuilder')
        result[:jbuilder] = jbuilder_files.size if jbuilder_files.any?

        files = path_resolver.files_for('app/serializers', extension: 'rb')
        result[:serializer_classes] = serializer_class_names(files) if files.any?

        result
      end

      def detect_graphql
        return nil unless path_resolver.directories_for('app/graphql').any? { |dir| Dir.exist?(dir) }

        types = path_resolver.glob_for('app/graphql', 'types/**/*.rb').size
        mutations = path_resolver.glob_for('app/graphql', 'mutations/**/*.rb').size
        queries = path_resolver.glob_for('app/graphql', 'queries/**/*.rb').size

        { types: types, mutations: mutations, queries: queries }
      end

      def detect_versioning
        path_resolver.glob_for('app/controllers', 'api/v*/').filter_map do |path|
          File.basename(path)
        end.sort
      end

      def detect_rate_limiting
        # Rack::Attack
        init_path = File.join(root, 'config/initializers/rack_attack.rb')
        return { rack_attack: true } if File.exist?(init_path)

        path_resolver.files_for('app/controllers', extension: 'rb').each do |path|
          content = File.read(path)
          return { rails_rate_limiting: true } if content.match?(/rate_limit\b/)
        rescue StandardError
          next
        end

        {}
      end

      def serializer_class_names(files)
        files.map do |file|
          path_resolver
            .logical_file_path(file, logical_path: 'app/serializers')
            .delete_prefix('app/serializers/')
            .sub(/\.rb\z/, '')
            .camelize
        end.sort
      end
    end
  end
end
