# frozen_string_literal: true

module RailsAiBridge
  # Orchestrates all sub-introspectors to build a complete
  # picture of the Rails application for AI consumption.
  class Introspector
    attr_reader :app, :config

    def initialize(app)
      @app    = app
      @config = RailsAiBridge.configuration
    end

    # Run all configured introspectors and return unified context hash
    #
    # @param only [Array<Symbol>, nil] optional subset of introspectors to execute
    # @return [Hash] complete application context or metadata + requested sections
    def call(only: nil)
      context = build_metadata

      names = selected_introspectors(only)
      results = if parallel_enabled? && names.size > 1
                  run_parallel(names)
                else
                  run_sequential(names)
                end

      context.merge(results)
    end

    BUILTIN_INTROSPECTORS = {
      schema: Introspectors::SchemaIntrospector,
      models: Introspectors::ModelIntrospector,
      non_ar_models: Introspectors::NonArModelsIntrospector,
      routes: Introspectors::RouteIntrospector,
      jobs: Introspectors::JobIntrospector,
      gems: Introspectors::GemIntrospector,
      conventions: Introspectors::ConventionDetector,
      stimulus: Introspectors::StimulusIntrospector,
      database_stats: Introspectors::DatabaseStatsIntrospector,
      controllers: Introspectors::ControllerIntrospector,
      views: Introspectors::ViewIntrospector,
      turbo: Introspectors::TurboIntrospector,
      i18n: Introspectors::I18nIntrospector,
      config: Introspectors::ConfigIntrospector,
      active_storage: Introspectors::ActiveStorageIntrospector,
      action_text: Introspectors::ActionTextIntrospector,
      auth: Introspectors::AuthIntrospector,
      api: Introspectors::ApiIntrospector,
      tests: Introspectors::TestIntrospector,
      rake_tasks: Introspectors::RakeTaskIntrospector,
      assets: Introspectors::AssetPipelineIntrospector,
      devops: Introspectors::DevOpsIntrospector,
      action_mailbox: Introspectors::ActionMailboxIntrospector,
      migrations: Introspectors::MigrationIntrospector,
      seeds: Introspectors::SeedsIntrospector,
      middleware: Introspectors::MiddlewareIntrospector,
      engines: Introspectors::EngineIntrospector,
      multi_database: Introspectors::MultiDatabaseIntrospector,
      semantic: Introspectors::SemanticIntrospector
    }.freeze

    def app_name
      if app.class.respond_to?(:module_parent_name)
        app.class.module_parent_name
      else
        app.class.name.deconstantize
      end
    end

    def selected_introspectors(only)
      names = Array(only).compact
      return config.effective_introspectors if names.empty?

      names
    end

    def resolve_introspector(name)
      introspector_class = config.additional_introspectors[name] || BUILTIN_INTROSPECTORS[name]
      raise ConfigurationError, "Unknown introspector: #{name}" unless introspector_class

      introspector_class.new(app)
    end

    private

    def build_metadata
      {
        app_name: app_name,
        ruby_version: RUBY_VERSION,
        rails_version: Rails.version,
        environment: Rails.env,
        generated_at: Time.current.iso8601,
        generator: "rails-ai-bridge v#{RailsAiBridge::VERSION}"
      }
    end

    def run_sequential(names)
      results = {}
      names.each do |name|
        introspector = resolve_introspector(name)
        results[name] = introspector.call
      rescue StandardError => error
        results[name] = { error: error.message }
        Rails.logger.warn "[rails-ai-bridge] #{name} introspection failed: #{error.message}"
      end
      results
    end

    def run_parallel(names)
      introspector_map = names.each_with_object({}) do |name, map|
        map[name] = resolve_introspector_class(name)
      end
      ParallelRunner.call(introspector_map, app)
    end

    def resolve_introspector_class(name)
      config.additional_introspectors[name] || BUILTIN_INTROSPECTORS[name] ||
        raise(ConfigurationError, "Unknown introspector: #{name}")
    end

    def parallel_enabled?
      config.parallel_introspection && ParallelRunner.available?
    end
  end
end
