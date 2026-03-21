# frozen_string_literal: true

module RailsAiBridge
  # File system watcher that regenerates bridge files when key files change.
  # Requires the `listen` gem (optional dependency).
  class Watcher
    DEBOUNCE_SECONDS = 2
    WATCH_PATTERNS = %w[
      app/models
      app/controllers
      app/jobs
      app/mailers
      app/javascript/controllers
      config
      db
    ].freeze

    attr_reader :app

    def initialize(app = nil)
      @app = app || Rails.application
      @last_fingerprint = Fingerprinter.compute(@app)
    end

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

    def handle_change
      return unless Fingerprinter.changed?(app, @last_fingerprint)

      @last_fingerprint = Fingerprinter.compute(app)

      $stderr.puts "[rails-ai-bridge] Changes detected, regenerating bridge files..."
      result = RailsAiBridge.generate_context(format: :all)
      result[:written].each { |f| $stderr.puts "  Updated: #{f}" }
      result[:skipped].each { |f| $stderr.puts "  Unchanged: #{f}" }
    rescue => e
      $stderr.puts "[rails-ai-bridge] Error regenerating: #{e.message}"
    end
  end
end
