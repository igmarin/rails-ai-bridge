# frozen_string_literal: true

require 'digest'

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
      # Computes a snapshot hash of file mtimes for watched files and directories.
      #
      # @param app [Rails::Application] the Rails application
      # @return [String] hex digest of the combined mtime fingerprint
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

          Dir.glob(File.join(full_dir, '**/*.{rb,rake,js,ts,erb,haml,slim,yml}')).each do |path|
            digest.update(File.mtime(path).to_f.to_s)
          end
        end

        digest.hexdigest
      end

      # Alias for +snapshot+. Used internally for a consistent API surface.
      #
      # @param app [Rails::Application] the Rails application
      # @return [String] hex digest fingerprint
      def compute(app)
        snapshot(app)
      end

      # Checks whether the application has changed since a previous snapshot.
      #
      # @param app [Rails::Application] the Rails application
      # @param previous [String] previous hex digest from +snapshot+
      # @return [Boolean] +true+ if the application has changed
      def changed?(app, previous)
        snapshot(app) != previous
      end

      # Computes a short content-based fingerprint (12 hex chars) from schema and routes.
      #
      # @param app [Rails::Application] the Rails application
      # @return [String] 12-character hex fingerprint
      def source_fingerprint(app)
        root = app.root
        paths = [schema_path(root), File.join(root, 'config/routes.rb')]
        Digest::SHA256.hexdigest(read_source_content(paths))[0...12]
      end

      private

      # Resolves the schema path, preferring +schema.rb+ over +structure.sql+.
      #
      # @param root [String] Rails application root path
      # @return [String] path to schema file
      def schema_path(root)
        rb_path = File.join(root, 'db/schema.rb')
        return rb_path if File.exist?(rb_path)

        File.join(root, 'db/structure.sql')
      end

      # Reads file contents with explicit per-file boundary markers for unambiguous hashing.
      # Missing files produce an empty labelled chunk so the marker is always present.
      #
      # @param paths [Array<String>] file paths to read
      # @return [String] combined content with separators between files
      def read_source_content(paths)
        paths.map do |path|
          label = "=== #{File.basename(path)} ===\n"
          content = File.exist?(path) ? File.read(path) : ''
          "#{label}#{content}\n---\n"
        end.join
      end
    end
  end
end
