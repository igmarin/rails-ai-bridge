# frozen_string_literal: true

module RailsAiBridge
  # Orchestrates all sub-introspectors to build a complete picture of the
  # Rails application for AI consumption.
  #
  # Depending on configuration, introspectors are run sequentially (default)
  # or concurrently via {ParallelRunner}. Sequential runs are timed via
  # {TimedRunner} so duration data is available in debug logs regardless of
  # the execution strategy.
  #
  # @example Running all standard introspectors
  #   context = RailsAiBridge::Introspector.new(Rails.application).call
  #   context[:app_name]  #=> "MyApp"
  #   context[:schema]    #=> { tables: { ... } }
  #
  # @example Running a subset of introspectors
  #   context = RailsAiBridge::Introspector.new(app).call(only: %i[schema routes])
  class Introspector
    # @return [Rails::Application] the host application passed at construction
    attr_reader :app

    # @return [RailsAiBridge::Configuration] active gem configuration
    attr_reader :config

    # @param app [Rails::Application] the Rails application to introspect
    def initialize(app)
      @app    = app
      @config = RailsAiBridge.configuration
    end

    # Runs all configured (or a specified subset of) introspectors and returns
    # a unified context hash.
    #
    # Metadata keys (+:app_name+, +:ruby_version+, +:rails_version+, etc.) are
    # always present. Introspector results are merged in at the top level, keyed
    # by their symbolic name (e.g. +:schema+, +:routes+).
    #
    # When parallel introspection is enabled *and* more than one introspector is
    # requested, execution is delegated to {ParallelRunner}. Otherwise each
    # introspector runs sequentially, wrapped by {TimedRunner} for observability.
    #
    # @param only [Array<Symbol>, nil] optional subset of introspector keys to
    #   run; passes through {#selected_introspectors}
    # @return [Hash] complete application context merged with metadata
    def call(only: nil)
      context = build_metadata

      names   = selected_introspectors(only)
      results = if parallel_enabled? && names.size > 1
                  run_parallel(names)
                else
                  run_sequential(names)
                end

      context.merge(results)
    end

    # Registry of all built-in introspector classes, keyed by symbolic name.
    #
    # The +:standard+ preset uses 9 of these; the +:full+ preset uses 26.
    # Opt-in-only keys (e.g. +:database_stats+, +:non_ar_models+) are present
    # here but excluded from both presets by default.
    #
    # @return [Hash{Symbol => Class}]
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

    # Returns the application name derived from the Rails application class.
    #
    # Tries +module_parent_name+ first (Rails 6+), falling back to
    # +deconstantize+ on the full class name.
    #
    # @return [String] the application module name (e.g. +"MyApp"+)
    def app_name
      if app.class.respond_to?(:module_parent_name)
        app.class.module_parent_name
      else
        app.class.name.deconstantize
      end
    end

    # Resolves the list of introspector keys to run.
    #
    # Returns +config.effective_introspectors+ when +only+ is blank; otherwise
    # returns the compact, de-nilified version of +only+.
    #
    # @param only [Array<Symbol>, nil]
    # @return [Array<Symbol>]
    def selected_introspectors(only)
      names = Array(only).compact
      return config.effective_introspectors if names.empty?

      names
    end

    # Looks up and instantiates an introspector by name.
    #
    # Checks +config.additional_introspectors+ before falling back to
    # {BUILTIN_INTROSPECTORS}.
    #
    # @param name [Symbol] introspector key
    # @return [Object] an instantiated introspector
    # @raise [ConfigurationError] if +name+ is not registered
    def resolve_introspector(name)
      introspector_class = config.additional_introspectors[name] || BUILTIN_INTROSPECTORS[name]
      raise ConfigurationError, "Unknown introspector: #{name}" unless introspector_class

      introspector_class.new(app)
    end

    private

    # Builds the fixed metadata hash prepended to every {#call} result.
    #
    # @return [Hash{Symbol => Object}]
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

    # Runs introspectors one at a time, each wrapped by {TimedRunner}.
    #
    # Duration is logged at +debug+ level so operators can spot slow
    # introspectors without changing the result structure.
    #
    # @param names [Array<Symbol>]
    # @return [Hash{Symbol => Object}]
    def run_sequential(names)
      names.index_with { |name| run_single(name) }
    end

    # Runs a single introspector by name, recording elapsed time via
    # {TimedRunner} and returning only the plain result to the caller.
    #
    # Any error raised by the introspector is captured by {TimedRunner} and
    # returned as +{ error: message }+.
    #
    # @param name [Symbol]
    # @return [Object] introspector result or +{ error: String }+ on failure
    def run_single(name)
      klass = resolve_introspector_class(name)
      timed = TimedRunner.call(klass, app)
      Rails.logger.debug { "[rails-ai-bridge] #{name} introspection completed in #{timed[:duration_ms]}ms" }
      timed[:result]
    end

    # Delegates concurrent execution to {ParallelRunner}.
    #
    # @param names [Array<Symbol>]
    # @return [Hash{Symbol => Object}]
    def run_parallel(names)
      introspector_map = names.index_with { |name| resolve_introspector_class(name) }
      ParallelRunner.call(introspector_map, app)
    end

    # Looks up the introspector *class* (not instance) for parallel scheduling.
    #
    # @param name [Symbol]
    # @return [Class]
    # @raise [ConfigurationError] if +name+ is not registered
    def resolve_introspector_class(name)
      config.additional_introspectors[name] || BUILTIN_INTROSPECTORS[name] ||
        raise(ConfigurationError, "Unknown introspector: #{name}")
    end

    # Returns +true+ when {ParallelRunner} is available and parallel
    # introspection is enabled in configuration.
    #
    # @return [Boolean]
    def parallel_enabled?
      config.parallel_introspection && ParallelRunner.available?
    end
  end
end
