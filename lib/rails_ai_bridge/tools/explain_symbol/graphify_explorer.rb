# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class ExplainSymbol
      # Runs local +graphify query+ against an on-disk +graphify-out/graph.json+
      # index. Uses {CliRunner} (argv arrays, wall-clock timeout, no network) and
      # surfaces failures as {ExploreError}.
      class GraphifyExplorer
        DEFAULT_TIMEOUT_SECONDS = 15

        # @param root [String] application root that should contain +graphify-out/graph.json+
        # @param timeout [Numeric] wall-clock seconds for the CLI (must be positive)
        def initialize(root:, timeout: DEFAULT_TIMEOUT_SECONDS)
          @root = root
          @timeout = timeout
        end

        # @param query [String] symbol or natural-language query for +graphify query+
        # @return [String] markdown from +graphify query+
        # @raise [ExploreError] when the CLI is missing, times out, or exits non-zero
        def explore(query)
          CliRunner.run(
            command: command_for(query),
            root: @root,
            timeout: @timeout,
            missing_message: 'graphify CLI not found on PATH',
            timeout_label: 'graphify query'
          )
        end

        private

        # @param query [String]
        # @return [Array<String>] argv for Open3 (never a single shell string)
        def command_for(query)
          ['graphify', 'query', query.to_s,
           '--graph', File.join(@root, 'graphify-out', 'graph.json'),
           '--budget', '2000']
        end
      end
    end
  end
end
