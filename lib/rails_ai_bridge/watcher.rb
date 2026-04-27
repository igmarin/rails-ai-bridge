# frozen_string_literal: true

module RailsAiBridge
  # File system watcher that regenerates bridge files when key files change.
  # Requires the +listen+ gem (optional dependency).
  #
  # Orchestrates {Watcher::WatchDirectories}, the Listen listener loop, and
  # {Watcher::BridgeRegenerator} for regeneration work.
  class Watcher
    # @return [Array<String>] relative path segments watched by default (same as {Watcher::WatchDirectories::DEFAULT_PATTERNS})
    WATCH_PATTERNS = WatchDirectories::DEFAULT_PATTERNS

    # @return [Rails::Application] host application
    attr_reader :app

    # @param app [Rails::Application, nil] defaults to +Rails.application+
    def initialize(app = nil)
      @app = app || Rails.application
      @regenerator = BridgeRegenerator.new(@app)
    end

    # Starts the Listen loop until SIGINT (Interrupt). Exits the process if +listen+ is missing.
    #
    # @return [void]
    def start
      require 'listen'

      root = app.root.to_s
      dirs = WatchDirectories.resolve(root)

      if dirs.empty?
        warn '[rails-ai-bridge] No watchable directories found'
        return
      end

      warn '[rails-ai-bridge] Watching for changes...'
      warn "[rails-ai-bridge] Directories: #{dirs.map { |d| d.sub("#{root}/", '') }.join(', ')}"

      listener = Listen.to(*dirs) do |modified, added, removed|
        next if (modified + added + removed).empty?

        handle_change
      end

      listener.start

      loop do
        sleep 1
      rescue Interrupt
        warn "\n[rails-ai-bridge] Stopping watcher..."
        listener.stop
        break
      end
    rescue LoadError
      warn 'Error: The `listen` gem is required for watch mode.'
      warn "Add to your Gemfile:  gem 'listen', group: :development"
      raise SystemExit, 1
    end

    private

    def handle_change
      return unless @regenerator.change_pending?

      warn '[rails-ai-bridge] Changes detected, regenerating bridge files...'
      result = @regenerator.regenerate!
      result[:written].each { |f| warn "  Updated: #{f}" }
      result[:skipped].each { |f| warn "  Unchanged: #{f}" }
    rescue StandardError => error
      warn "[rails-ai-bridge] Error regenerating: #{error.message}"
    end
  end
end
