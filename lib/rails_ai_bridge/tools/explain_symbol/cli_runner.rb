# frozen_string_literal: true

require 'open3'
require 'timeout'

module RailsAiBridge
  module Tools
    class ExplainSymbol
      # Shared local-CLI execution for code-intelligence explorers. Runs an argv
      # array (no shell) under a wall-clock timeout with offline-friendly
      # environment flags. Never opens a network connection.
      module CliRunner
        # @param command [Array<String>] argv to execute
        # @param root [String] directory to run the command in
        # @param timeout [Numeric] wall-clock seconds
        # @param missing_message [String] error detail used when the binary is not on PATH
        # @param timeout_label [String] command label used in the timeout message
        # @return [String] combined stdout of the command
        # @raise [ExploreError] when the CLI is missing, times out, or exits non-zero
        # :reek:LongParameterList -- the five args describe one subprocess invocation
        # :reek:TooManyStatements { exclude: [run] } -- guard -> execute -> classify flow
        def self.run(command:, root:, timeout:, missing_message:, timeout_label:)
          stdout, stderr, status = Timeout.timeout(timeout) do
            Open3.capture3(offline_env, *command, chdir: root)
          end
          return stdout.to_s if status.success?

          detail = stderr.to_s.strip
          raise ExploreError, detail.empty? ? "exit #{status.exitstatus}" : detail
        rescue Errno::ENOENT
          raise ExploreError, missing_message
        rescue Timeout::Error
          raise ExploreError, "#{timeout_label} timed out after #{timeout} seconds"
        end

        # Environment flags that keep CLIs from coloring output or sending telemetry.
        #
        # @return [Hash{String=>String}]
        def self.offline_env
          { 'NO_COLOR' => '1', 'DO_NOT_TRACK' => '1' }
        end
      end
    end
  end
end
