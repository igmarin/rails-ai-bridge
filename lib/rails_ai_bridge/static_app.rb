# frozen_string_literal: true

require 'pathname'

module RailsAiBridge
  # A minimal app-like object for static mode (no Rails boot).
  #
  # Exposes only +root+, +paths+, +config+, and +eager_load!+ so that
  # static-capable introspectors (schema, gems, tests, migrations) can
  # operate without a booted Rails application. Boot-required introspectors
  # (models, routes, controllers, etc.) are identified via the capability
  # map and report "not available without boot" when invoked in static mode.
  #
  # @example Static introspection
  #   app = RailsAiBridge::StaticApp.new('/path/to/app')
  #   RailsAiBridge::AppScope.with_app(app) do
  #     RailsAiBridge.introspect(app, only: [:schema, :gems])
  #   end
  #
  class StaticApp
    # Introspectors that work with only file system access (no Rails boot).
    STATIC_CAPABLE = %i[schema gems tests migrations conventions].freeze

    # Introspectors that require a fully booted Rails application.
    BOOT_REQUIRED = %i[
      models non_ar_models routes jobs controllers views stimulus
      i18n config active_storage action_text auth api rake_tasks
      assets devops action_mailbox seeds middleware engines
      multi_database semantic database_stats
    ].freeze

    # Conventional Rails path mappings used when app.paths is unavailable.
    CONVENTIONAL_PATHS = {
      'app/models' => 'app/models',
      'app/controllers' => 'app/controllers',
      'app/views' => 'app/views',
      'app/jobs' => 'app/jobs',
      'app/mailers' => 'app/mailers',
      'app/helpers' => 'app/helpers',
      'app/assets' => 'app/assets',
      'config' => 'config',
      'db' => 'db',
      'lib' => 'lib',
      'test' => 'test',
      'spec' => 'spec'
    }.freeze

    StaticConfig = Struct.new(:api_only, :eager_load) do
      def initialize
        super(false, false)
      end
    end

    private_constant :StaticConfig

    # @return [Pathname] the application root
    attr_reader :root

    # @return [StaticConfig] a minimal config stub
    attr_reader :config

    # @param root [String, Pathname] the application root path
    def initialize(root)
      @root = Pathname.new(root)
      @config = StaticConfig.new
    end

    # No-op — static mode does not eager load anything.
    #
    # @return [nil]
    def eager_load!
      nil
    end

    # Non-bang counterpart for {#eager_load!}. Also a no-op in static mode.
    #
    # @return [nil]
    def eager_load
      nil
    end

    # Returns conventional Rails paths rooted at the static app root.
    #
    # @return [Hash{String => Array<String>}]
    def paths
      @paths ||= CONVENTIONAL_PATHS.transform_values { |rel| [root.join(rel).to_s] }
    end

    class << self
      # Checks whether a given introspector section is available in static mode.
      #
      # @param section [Symbol] the introspector key
      # @return [Boolean]
      def static_available?(section)
        STATIC_CAPABLE.include?(section)
      end
    end
  end
end
