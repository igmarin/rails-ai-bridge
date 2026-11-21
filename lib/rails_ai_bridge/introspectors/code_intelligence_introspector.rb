# frozen_string_literal: true

require 'open3'
require 'timeout'

module RailsAiBridge
  module Introspectors
    # Reports whether local code intelligence indexes (CodeGraph or Graphify)
    # are present in the application, when they were last generated, and
    # whether the Graphify graph is stale relative to the current HEAD.
    # Read-only: inspects files and runs `git rev-parse`; never writes.
    class CodeIntelligenceIntrospector
      attr_reader :app

      # Matches `Built from commit: `<sha>`` lines in GRAPH_REPORT.md (7–40 hex chars).
      COMMIT_LINE_PATTERN = /Built from commit:\s*`([0-9a-f]{7,40})`/i

      def initialize(app)
        @app = app
      end

      # @return [Hash] index presence, timestamps, commit staleness
      def call
        {
          codegraph: codegraph_info,
          graphify: graphify_info
        }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def root
        app.root.to_s
      end

      # @return [Hash]
      def codegraph_info
        path = '.codegraph/codegraph.db'
        {
          present: Dir.exist?(File.join(root, '.codegraph')),
          index_path: path,
          indexed_at: mtime_of(path)
        }
      end

      # @return [Hash]
      def graphify_info
        path = 'graphify-out/graph.json'
        {
          present: File.exist?(File.join(root, path)),
          graph_path: path,
          generated_at: mtime_of(path),
          graph_commit: graph_commit,
          head_commit: head_commit,
          stale: stale?
        }
      end

      # @param relative_path [String]
      # @return [Time, nil]
      def mtime_of(relative_path)
        full = File.join(root, relative_path)
        File.exist?(full) ? File.mtime(full) : nil
      end

      # Parsed lazily so a missing report costs one File.exist? check.
      # @return [String, nil] 40-char SHA parsed from GRAPH_REPORT.md, or nil
      # :reek:TooManyStatements { exclude: [graph_commit] } -- single-purpose parse with guards
      def graph_commit
        report_path = File.join(root, 'graphify-out', 'GRAPH_REPORT.md')
        return unless File.exist?(report_path)

        report = File.foreach(report_path)
        commit_line = report.find { |line| line.include?('Built from commit:') }
        return unless commit_line

        commit_line.match(COMMIT_LINE_PATTERN)&.captures&.first
      rescue StandardError
        nil
      end

      # @return [String, nil] HEAD SHA, or nil outside a repo / on any failure
      def head_commit
        stdout, _stderr, status = Timeout.timeout(5) do
          Open3.capture3('git', 'rev-parse', 'HEAD', chdir: root)
        end
        status.success? ? stdout.strip : nil
      rescue StandardError
        nil
      end

      # nil when either commit is unknown; comparison is 7-char prefixed so
      # short report SHAs still match a full HEAD.
      # @return [Boolean, nil] nil means "unknown", not false
      # rubocop:disable-next Style/ReturnNilInPredicateMethodDefinition
      def stale?
        return nil unless graph_commit && head_commit

        !head_commit.start_with?(graph_commit[0, 7])
      end
    end
  end
end
