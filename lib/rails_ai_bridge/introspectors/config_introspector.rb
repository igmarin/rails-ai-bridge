# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts application configuration: cache store, session store,
    # timezone, middleware stack, initializers, credentials keys.
    class ConfigIntrospector
      attr_reader :app, :path_resolver

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
        @timezone_introspector = Introspectors::TimezoneIntrospector.new(app)
      end

      # Builds a read-only summary of runtime configuration signals.
      #
      # @return [Hash] cache, session, middleware, initializer, and CurrentAttributes metadata
      # @example With timezone
      #   {
      #     cache_store: "mem_cache_store",
      #     session_store: "ActionDispatch::Session::CookieStore",
      #     timezone: "UTC",
      #     timezone_source: :config,
      #     ...middleware_stack, :initializers, :current_attributes
      #   }
      def call
        tz = @timezone_introspector.call

        result = {
          cache_store: detect_cache_store,
          session_store: detect_session_store,
          queue_adapter: detect_queue_adapter,
          cable_adapter: detect_cable_adapter,
          timezone: tz[:time_zone],
          timezone_source: tz[:time_zone_source],
          timezone_confirmed: tz[:time_zone_confirmed],
          timezone_found: tz.key?(:time_zone),
          middleware_stack: extract_middleware,
          initializers: extract_initializers,
          current_attributes: detect_current_attributes
        }
        result[:credentials_keys] = extract_credentials_keys if RailsAiBridge.configuration.expose_credentials_key_names
        result
      rescue StandardError => error
        { error: error.message }
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

      def detect_queue_adapter
        return 'unknown' unless app.config.respond_to?(:active_job)

        adapter = app.config.active_job&.queue_adapter
        adapter.is_a?(Symbol) ? adapter.to_s : adapter.class.name
      rescue StandardError
        'unknown'
      end

      def detect_cable_adapter
        return 'unknown' unless app.config.respond_to?(:action_cable)

        adapter = app.config.action_cable&.adapter
        adapter.is_a?(Symbol) ? adapter.to_s : adapter.class.name
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
        path_resolver.files_for('app/models', extension: 'rb').filter_map do |path|
          content = File.read(path)
          File.basename(path, '.rb').camelize if content.match?(/< ActiveSupport::CurrentAttributes|< Rails::CurrentAttributes/)
        rescue StandardError
          nil
        end
      end
    end
  end
end
