# frozen_string_literal: true

module RailsAiBridge
  # Diagnostic checker that validates the environment and reports
  # AI readiness with pass/warn/fail checks and a readiness score.
  class Doctor
    # Maps stable check identifiers to checker classes. Each value must implement
    # +.call+ on an instance and return a {Doctor::Check}.
    CHECKS = {
      check_schema: Checkers::SchemaChecker,
      check_models: Checkers::ModelsChecker,
      check_routes: Checkers::RoutesChecker,
      check_gems: Checkers::GemsChecker,
      check_controllers: Checkers::ControllersChecker,
      check_views: Checkers::ViewsChecker,
      check_i18n: Checkers::I18nChecker,
      check_tests: Checkers::TestsChecker,
      check_migrations: Checkers::MigrationsChecker,
      check_context_files: Checkers::ContextFilesChecker,
      check_bridge_freshness: Checkers::BridgeFreshnessChecker,
      check_mcp_buildable: Checkers::McpBuildableChecker,
      check_ripgrep: Checkers::RipgrepChecker,
      check_view_mcp_tool: Checkers::ViewMcpToolChecker,
      check_stimulus_mcp_tool: Checkers::StimulusMcpToolChecker,
      check_bridge_metadata: Checkers::BridgeMetadataChecker,
      check_registry: Checkers::RegistryChecker
    }.freeze

    STATIC_UNAVAILABLE_CHECKS = {
      check_models: 'Models',
      check_routes: 'Routes',
      check_controllers: 'Controllers',
      check_views: 'Views',
      check_i18n: 'I18n'
    }.freeze
    private_constant :STATIC_UNAVAILABLE_CHECKS

    attr_reader :app, :boot_result

    # Boots an application and runs diagnostics, using static fallback on failure.
    #
    # @param root [String, Pathname] application root
    # @param timeout [Numeric] maximum boot duration in seconds
    # @return [Hash] diagnostic result with `:checks` and `:score`
    def self.run_for(root, timeout: BootManager::DEFAULT_TIMEOUT)
      boot_result = BootManager.boot(root, timeout: timeout)
      app = boot_result[:success] ? boot_result[:app] : BootManager.static_fallback(root)
      new(app, boot_result: boot_result).run
    end

    # @param app [Rails::Application, nil] application to inspect
    # @param boot_result [Hash, nil] structured result from {BootManager.boot}
    # @return [void]
    def initialize(app = nil, boot_result: nil)
      @app = app || AppScope.current_app
      @boot_result = boot_result
    end

    # Runs all diagnostic checks and computes a readiness score.
    #
    # @return [Hash] diagnostic result with `:checks` and `:score`
    def run
      results = CHECKS.map { |name, checker_class| run_check(name, checker_class) }
      results.unshift(boot_failure_check) if boot_failed?
      score = compute_score(results)
      { checks: results, score: score }
    end

    private

    def boot_failed?
      boot_result && !boot_result[:success]
    end

    def boot_failure_check
      error_class = boot_result[:error_class].presence || 'UnknownError'
      Check.new(
        name: 'Rails boot',
        status: :fail,
        message: "Rails boot failed (#{error_class})",
        fix: nil
      )
    end

    def run_check(name, checker_class)
      unavailable_name = STATIC_UNAVAILABLE_CHECKS[name]
      return checker_class.new(app).call unless app.is_a?(StaticApp) && unavailable_name

      Check.new(
        name: unavailable_name,
        status: :warn,
        message: 'Not available without Rails boot',
        fix: nil
      )
    end

    # Weighted score: +:pass+ 10, +:warn+ 5, other 0; scaled to 0–100.
    #
    # @param results [Array<Doctor::Check>]
    # @return [Integer] readiness percentage (rounded)
    def compute_score(results)
      total = results.size * 10
      earned = results.sum do |check|
        case check.status
        when :pass then 10
        when :warn then 5
        else 0
        end
      end
      ((earned.to_f / total) * 100).round
    end
  end
end
