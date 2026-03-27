# frozen_string_literal: true

module RailsAiBridge
  # Watches a fixed set of project directories and regenerates bridge files when the
  # {Fingerprinter} detects a meaningful change.
  #
  # Depends on the +listen+ gem, which is **not** a runtime dependency of rails-ai-bridge: add
  # +gem "listen", group: :development+ to the **host application** (or rely on Rails’ default
  # development group, which often includes it). The gem declares +listen+ only as a
  # development dependency for maintainers and CI.
  #
  # @see Fingerprinter
  # @see RailsAiBridge.generate_context
  class Watcher
    # Reserved interval (seconds) for future debouncing; regeneration is currently gated by
    # fingerprint comparison in {#handle_change}.
    DEBOUNCE_SECONDS = 2

    # Subpaths under +Rails.root+ passed to +Listen+. Only existing directories are watched.
    #
    # @return [Array<String>]
    WATCH_PATTERNS = %w[
      app/models
      app/controllers
      app/jobs
      app/mailers
      app/javascript/controllers
      config
      db
    ].freeze

    # @return [Rails::Application]
    attr_reader :app

    # @param app [Rails::Application, nil] defaults to +Rails.application+
    def initialize(app = nil)
      @app = app || Rails.application
      @last_fingerprint = Fingerprinter.compute(@app)
    end

    # Starts +Listen+ on {WATCH_PATTERNS}, then blocks in a sleep loop until SIGINT (+Interrupt+).
    #
    # Calls {RailsAiBridge.generate_context} with +format: :install+ when the fingerprint changes.
    #
    # @return [void] may return early when no watchable directories exist
    # @note On missing +listen+, prints to stderr and calls +exit(1)+.
    # @note This method does not return normally unless no directories are watchable.
    def start
      require "listen"

      root = app.root.to_s
      dirs = WATCH_PATTERNS.map { |p| File.join(root, p) }.select { |d| Dir.exist?(d) }

      if dirs.empty?
        $stderr.puts "[rails-ai-bridge] No watchable directories found"
        return
      end

      $stderr.puts "[rails-ai-bridge] Watching for changes..."
      $stderr.puts "[rails-ai-bridge] Directories: #{dirs.map { |d| d.sub("#{root}/", '') }.join(', ')}"

      listener = Listen.to(*dirs) do |modified, added, removed|
        next if (modified + added + removed).empty?
        handle_change
      end

      listener.start

      # Keep the process alive
      loop do
        sleep 1
      rescue Interrupt
        $stderr.puts "\n[rails-ai-bridge] Stopping watcher..."
        listener.stop
        break
      end
    rescue LoadError
      $stderr.puts "Error: The `listen` gem is required for watch mode."
      $stderr.puts "Add to your Gemfile:  gem 'listen', group: :development"
      exit 1
    end

    private

    # Regenerates context when {Fingerprinter.changed?} is true; updates the cached fingerprint.
    #
    # @return [void]
    def handle_change
      return unless Fingerprinter.changed?(app, @last_fingerprint)

      @last_fingerprint = Fingerprinter.compute(app)

      $stderr.puts "[rails-ai-bridge] Changes detected, regenerating bridge files..."
      result = RailsAiBridge.generate_context(format: :install)
      result[:written].each { |f| $stderr.puts "  Updated: #{f}" }
      result[:skipped].each { |f| $stderr.puts "  Unchanged: #{f}" }
    rescue => e
      $stderr.puts "[rails-ai-bridge] Error regenerating: #{e.message}"
    end
  end
end
