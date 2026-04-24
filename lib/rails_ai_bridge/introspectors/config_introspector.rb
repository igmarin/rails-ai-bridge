# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts application configuration: cache store, session store,
    # timezone, middleware stack, initializers, credentials keys.
    class ConfigIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        result = {
          cache_store: detect_cache_store,
          session_store: detect_session_store,
          timezone: app.config.time_zone.to_s,
          middleware_stack: extract_middleware,
          initializers: extract_initializers,
          current_attributes: detect_current_attributes
        }
        result[:credentials_keys] = extract_credentials_keys if RailsAiBridge.configuration.expose_credentials_key_names
        result
      rescue StandardError => e
        { error: e.message }
      end

      private

      def root
        app.root.to_s
      end

      def detect_cache_store
        store = app.config.cache_store
        case store
        when Symbol then store.to_s
        when Array then store.first.to_s
        else store.class.name
        end
      rescue StandardError
        'unknown'
      end

      def detect_session_store
        app.config.session_store&.name
      rescue StandardError
        'unknown'
      end

      def extract_middleware
        app.middleware.map { |m| m.name || m.klass.to_s }.uniq
      rescue StandardError
        []
      end

      def extract_initializers
        dir = File.join(root, 'config/initializers')
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '*.rb')).map { |f| File.basename(f) }.sort
      end

      def extract_credentials_keys
        creds = app.credentials
        return [] unless creds.respond_to?(:config)

        creds.config.keys.map(&:to_s).sort
      rescue StandardError
        []
      end

      def detect_current_attributes
        models_dir = File.join(root, 'app/models')
        return [] unless Dir.exist?(models_dir)

        Dir.glob(File.join(models_dir, '**/*.rb')).filter_map do |path|
          content = File.read(path)
          File.basename(path, '.rb').camelize if content.match?(/< ActiveSupport::CurrentAttributes|< Rails::CurrentAttributes/)
        rescue StandardError
          nil
        end
      end
    end
  end
end
