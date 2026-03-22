# frozen_string_literal: true

require "digest"

module RailsAiBridge
  # Computes a SHA256 fingerprint of key application files to detect changes.
  # Used by BaseTool to invalidate cached introspection when files change.
  class Fingerprinter
    WATCHED_FILES = %w[
      db/schema.rb
      config/routes.rb
      config/database.yml
      Gemfile.lock
    ].freeze

    WATCHED_DIRS = %w[
      app/models
      app/controllers
      app/views
      app/jobs
      app/mailers
      app/channels
      app/javascript/controllers
      app/middleware
      config/initializers
      db/migrate
      lib/tasks
    ].freeze

    class << self
      def snapshot(app)
        root = app.root.to_s
        digest = Digest::SHA256.new

        WATCHED_FILES.each do |file|
          path = File.join(root, file)
          digest.update(File.mtime(path).to_f.to_s) if File.exist?(path)
        end

        WATCHED_DIRS.each do |dir|
          full_dir = File.join(root, dir)
          next unless Dir.exist?(full_dir)

          Dir.glob(File.join(full_dir, "**/*.{rb,rake,js,ts,erb,haml,slim,yml}")).sort.each do |path|
            digest.update(File.mtime(path).to_f.to_s)
          end
        end

        digest.hexdigest
      end

      def compute(app)
        snapshot(app)
      end

      def changed?(app, previous)
        snapshot(app) != previous
      end
    end
  end
end
