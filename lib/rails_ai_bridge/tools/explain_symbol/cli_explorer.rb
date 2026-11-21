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
          CliRunner.run(
            command: command_for(query),
            root: @root,
            timeout: @timeout,
            missing_message: 'codegraph CLI not found on PATH',
            timeout_label: 'codegraph explore'
          )
        end

        private

        # @param query [String]
        # @return [Array<String>] argv for Open3 (never a single shell string)
        def command_for(query)
          # `--` keeps flag-like queries (`-p /`, `--path=/tmp`) from overriding --path.
          ['codegraph', '--no-color', 'explore', '--path', @root, '--', query.to_s]
        end
      end
    end
  end
end
