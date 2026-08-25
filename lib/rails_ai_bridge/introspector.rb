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
  # :reek:RepeatedConditional -- static_mode? guards in build_metadata/run_single/run_parallel are the cleanest way to branch on app type
  class Introspector
    # @return [Rails::Application] the host application passed at construction
    attr_reader :app

    # @return [RailsAiBridge::Configuration] active gem configuration
    attr_reader :config

    # @param app [Rails::Application] the Rails application to introspect
    def initialize(app)
      @app    = app
      # archspec:disable dependencies.forbid -- FP: RailsAiBridge namespace accessor, not a cross-component dependency
      # archspec:disable dependencies.no_cycles -- FP: cycle from namespace reopening, not a real cross-component cycle
      @config = RailsAiBridge.configuration
      # archspec:enable dependencies.forbid
      # archspec:enable dependencies.no_cycles
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
    # The +:standard+ preset uses 9 of these; the +:full+ preset uses 27.
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
    # Returns +config.effective_introspectors+ when +only+ is blank. A non-blank
    # +only+ list is intersected with +effective_introspectors+ (plus
    # +additional_introspectors+ keys) so MCP +fetch_section+ cannot run
    # schema or models when they were disabled by +:regulated+ or
    # +disabled_introspection_categories+, while host-registered extras
    # remain fetchable.
    #
    # @param only [Array<Symbol>, nil]
    # @return [Array<Symbol>]
    def selected_introspectors(only)
      allowed = config.effective_introspectors
      names = Array(only).compact
      return allowed if names.empty?

      extra = config.additional_introspectors.keys
      names.select { |name| allowed.include?(name) || extra.include?(name) }
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
        rails_version: static_mode? ? detect_rails_version_from_gemfile : Rails.version,
        environment: static_mode? ? 'static' : Rails.env.to_s,
        generated_at: (static_mode? ? Time.now.utc : Time.current).iso8601,
        generator: "rails-ai-bridge v#{RailsAiBridge::VERSION}",
        static_mode: static_mode?
      }
    end

    # Detects the Rails version from the app's Gemfile.lock without booting.
    #
    # @return [String, nil]
    # :reek:FeatureEnvy -- lockfile is a Pathname, method is short
    def detect_rails_version_from_gemfile
      lockfile = app.root.join('Gemfile.lock')
      return nil unless lockfile.exist?

      lockfile.read.match(/^\s+rails\s+\(([^)]+)\)/)&.captures&.first
    rescue StandardError
      nil
    end

    # Returns a logger that is safe in both booted and static mode.
    # In static mode, Rails.logger may not be available.
    #
    # @return [Logger, nil]
    # :reek:ManualDispatch -- checking Rails.respond_to? is the safe way to guard static mode
    # :reek:UtilityFunction -- intentional: no instance state needed, just a safe accessor
    def logger
      defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end

    # Returns true when the app is a {StaticApp} (no Rails boot).
    #
    # @return [Boolean]
    def static_mode?
      @static_mode ||= app.is_a?(RailsAiBridge::StaticApp)
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
    # :reek:TooManyStatements -- static guard adds one branch, still readable
    def run_single(name)
      return static_unavailable_result(name) if static_mode? && !StaticApp.static_available?(name)

      klass = resolve_introspector_class(name)
      timed = TimedRunner.call(klass, app)
      logger&.debug { "[rails-ai-bridge] #{name} introspection completed in #{timed[:duration_ms]}ms" }
      timed[:result]
    end

    # Returns an honest "not available" result for boot-required
    # introspectors when running in static mode.
    #
    # @param name [Symbol]
    # @return [Hash{Symbol => String}]
    def static_unavailable_result(name)
      { error: "#{name} is not available without boot — use StaticApp only for static-capable sections" }
    end

    # Delegates concurrent execution to {ParallelRunner}.
    #
    # @param names [Array<Symbol>]
    # @return [Hash{Symbol => Object}]
    def run_parallel(names)
      return run_sequential(names) if static_mode?

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
