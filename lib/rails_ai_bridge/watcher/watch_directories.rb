# frozen_string_literal: true

module RailsAiBridge
  class Watcher
    # Resolves which configured relative paths exist under a Rails application root.
    # Single responsibility: directory discovery for the file listener.
    class WatchDirectories
      DEFAULT_PATTERNS = %w[
        app/models
        app/controllers
        app/jobs
        app/mailers
        app/javascript/controllers
        config
        db
      ].freeze

      # @param root [String, Pathname] application root
      # @param patterns [Array<String>] path segments relative to +root+
      # @return [Array<String>] absolute paths that exist on disk
      def self.resolve(root, patterns: DEFAULT_PATTERNS)
        base = root.to_s
        patterns.map { |p| File.join(base, p) }.select { |d| Dir.exist?(d) }
      end
    end
  end
end
