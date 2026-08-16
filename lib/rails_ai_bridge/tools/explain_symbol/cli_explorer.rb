# frozen_string_literal: true

require 'open3'
require 'timeout'

module RailsAiBridge
  module Tools
    class ExplainSymbol
      # Runs local +codegraph explore+ against an on-disk +.codegraph/+ index.
      # Uses argv arrays (no shell) and a wall-clock timeout. Never opens a network
      # connection — failures surface as {ExploreError}.
      class CliExplorer
        DEFAULT_TIMEOUT_SECONDS = 15

        # @param root [String] application root that should contain +.codegraph/+
        # @param timeout [Numeric] wall-clock seconds for the CLI (must be positive)
        def initialize(root:, timeout: DEFAULT_TIMEOUT_SECONDS)
          @root = root
          @timeout = timeout
        end

        # @param query [String] symbol or natural-language explore query
        # @return [String] markdown from +codegraph explore+
        # @raise [ExploreError] when the CLI is missing, times out, or exits non-zero
        def explore(query)
          stdout, stderr, status = run_explore(query)
          return stdout.to_s if status.success?

          raise ExploreError, failure_detail(stderr, status)
        rescue Errno::ENOENT
          raise ExploreError, 'codegraph CLI not found on PATH'
        rescue Timeout::Error
          raise ExploreError, "codegraph explore timed out after #{@timeout} seconds"
        end

        private

        # @param query [String]
        # @return [Array(String, String, Process::Status)]
        def run_explore(query)
          Timeout.timeout(@timeout) do
            Open3.capture3(offline_env, *command_for(query), chdir: @root)
          end
        end

        # @param query [String]
        # @return [Array<String>] argv for Open3 (never a single shell string)
        def command_for(query)
          # `--` keeps flag-like queries (`-p /`, `--path=/tmp`) from overriding --path.
          ['codegraph', '--no-color', 'explore', '--path', @root, '--', query.to_s]
        end

        # Environment flags that keep the CLI from coloring output or sending telemetry.
        #
        # @return [Hash{String=>String}]
        def offline_env
          { 'NO_COLOR' => '1', 'DO_NOT_TRACK' => '1' }
        end

        # @param stderr [String]
        # @param status [Process::Status]
        # @return [String]
        def failure_detail(stderr, status)
          detail = stderr.to_s.strip
          detail.empty? ? "exit #{status.exitstatus}" : detail
        end
      end
    end
  end
end
