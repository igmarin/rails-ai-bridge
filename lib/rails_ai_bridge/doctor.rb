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
      check_mcp_buildable: Checkers::McpBuildableChecker,
      check_ripgrep: Checkers::RipgrepChecker,
      check_view_mcp_tool: Checkers::ViewMcpToolChecker,
      check_stimulus_mcp_tool: Checkers::StimulusMcpToolChecker,
      check_bridge_metadata: Checkers::BridgeMetadataChecker
    }.freeze

    attr_reader :app

    # @param app [Rails::Application, nil] application to inspect
    # @return [void]
    def initialize(app = nil)
      @app = app || Rails.application
    end

    # Runs all diagnostic checks and computes a readiness score.
    #
    # @return [Hash] diagnostic result with `:checks` and `:score`
    def run
      results = CHECKS.values.map { |checker_class| checker_class.new(app).call }
      score = compute_score(results)
      { checks: results, score: score }
    end

    private

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
