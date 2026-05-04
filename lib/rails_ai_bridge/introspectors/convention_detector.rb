# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Detects high-level Rails conventions and patterns in use,
    # giving AI assistants critical context about the app's architecture.
    class ConventionDetector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      # Builds a read-only summary of high-level Rails conventions.
      #
      # @return [Hash] detected conventions and patterns, or an +:error+ key when detection fails
      def call
        {
          architecture: detect_architecture,
          patterns: detect_patterns,
          directory_structure: scan_directory_structure,
          config_files: detect_config_files
        }
      end

      private

      def root
        app.root.to_s
      end

      # Detects high-level architecture features from configured Rails paths and known files.
      #
      # @return [Array<String>] architecture identifiers such as +service_objects+ and +hotwire+
      def detect_architecture
        arch = []
        arch << 'api_only' if app.config.api_only
        arch << 'hotwire' if dir_exists?('app/javascript/controllers') || gem_present?('turbo-rails')
        arch << 'graphql' if dir_exists?('app/graphql')
        arch << 'grape_api' if dir_exists?('app/api')
        arch << 'service_objects' if dir_exists?('app/services')
        arch << 'form_objects' if dir_exists?('app/forms')
        arch << 'query_objects' if dir_exists?('app/queries')
        arch << 'presenters' if dir_exists?('app/presenters') || dir_exists?('app/decorators')
        arch << 'view_components' if dir_exists?('app/components')
        arch << 'phlex' if gem_present?('phlex-rails')
        arch << 'stimulus' if dir_exists?('app/javascript/controllers')
        arch << 'importmaps' if file_exists?('config/importmap.rb')
        arch << 'concerns_models' if dir_exists?('app/models/concerns')
        arch << 'concerns_controllers' if dir_exists?('app/controllers/concerns')
        arch << 'validators' if dir_exists?('app/validators')
        arch << 'policies' if dir_exists?('app/policies')
        arch << 'serializers' if dir_exists?('app/serializers')
        arch << 'notifiers' if dir_exists?('app/notifiers')
        arch << 'pwa' if file_exists?('app/views/pwa')
        arch << 'docker' if file_exists?('Dockerfile') || file_exists?('docker-compose.yml')
        arch << 'kamal' if file_exists?('config/deploy.yml')
        arch << 'ci_github_actions' if dir_exists?('.github/workflows')
        arch
      end

      # Detects source-level patterns from model files and path-level conventions.
      # Model files are resolved through configured Rails paths before falling back
      # to conventional +app/models+.
      #
      # @return [Array<String>] pattern identifiers such as +encrypted_attributes+
      def detect_patterns
        patterns = []

        # Check for common Rails patterns in model files
        model_files = files_for('app/models', extension: 'rb')
        if model_files.any?
          content = model_files.first(50).map do |file|
            File.read(file)
          rescue StandardError
            ''
          end.join("\n")

          patterns << 'sti' if content.match?(/self\.inheritance_column|type.*string/)
          patterns << 'polymorphic' if content.match?(/polymorphic:\s*true/)
          patterns << 'soft_delete' if content.match?(/acts_as_paranoid|discard|deleted_at/)
          patterns << 'versioning' if content.match?(/has_paper_trail|audited/)
          patterns << 'state_machine' if content.match?(/aasm|state_machine|workflow/)
          patterns << 'multi_tenancy' if content.match?(/acts_as_tenant|apartment/)
          patterns << 'searchable' if content.match?(/searchkick|pg_search|ransack/)
          patterns << 'taggable' if content.match?(/acts_as_taggable/)
          patterns << 'sluggable' if content.match?(/friendly_id|sluggable/)
          patterns << 'nested_set' if content.match?(/acts_as_nested_set|ancestry|closure_tree/)
          patterns << 'current_attributes' if content.match?(/< ActiveSupport::CurrentAttributes/)
          patterns << 'encrypted_attributes' if content.match?(/\bencrypts\s+:/)
          patterns << 'normalizations' if content.match?(/\bnormalizes\s+:/)
        end

        patterns << 'view_components' if dir_exists?('app/components')
        patterns << 'phlex' if gem_present?('phlex-rails')

        patterns
      end

      # Counts notable project directories using logical Rails path names.
      # Custom Rails paths are counted under their logical key (for example
      # +app/services+) so generated context does not leak absolute local paths.
      #
      # @return [Hash{String => Integer}] logical directory names mapped to file counts
      def scan_directory_structure
        important_dirs = %w[
          app/models app/controllers app/views app/jobs
          app/mailers app/channels app/services app/forms
          app/queries app/presenters app/decorators
          app/components app/graphql app/api
          app/policies app/serializers app/validators
          app/notifiers app/mailboxes
          app/javascript/controllers
          config/initializers db/migrate lib/tasks
          spec test
        ]

        important_dirs.each_with_object({}) do |dir, hash|
          count = count_files_for(dir)

          hash[dir] = count if count.positive?
        end
      end

      # Detects safe, notable config files present in the app root.
      #
      # @return [Array<String>] relative config file paths
      def detect_config_files
        configs = %w[
          config/database.yml
          config/cable.yml config/storage.yml
          config/sidekiq.yml config/deploy.yml
          config/importmap.rb config/tailwind.config.js
          config/puma.rb config/application.rb
          config/locales/en.yml
          package.json Gemfile
          Procfile Procfile.dev
          .rubocop.yml .rspec
          Dockerfile docker-compose.yml
          .github/workflows/ci.yml
        ]

        configs.select { |f| file_exists?(f) }
      end

      # Checks whether a logical Rails path exists in either configured paths or
      # the conventional app-root-relative location.
      #
      # @param relative_path [String] logical Rails path, such as +"app/services"+
      # @return [Boolean] true when at least one matching directory exists
      def dir_exists?(relative_path)
        directory_paths(relative_path).any? { |path| Dir.exist?(path) }
      end

      # Checks whether a root-relative file exists.
      #
      # @param relative_path [String] file path relative to the Rails root
      # @return [Boolean] true when the file exists
      def file_exists?(relative_path)
        File.exist?(File.join(root, relative_path))
      end

      # Resolves filesystem directories for a logical Rails path.
      # Uses configured +app.paths+ entries first and falls back to the conventional
      # root-relative path when no custom path is configured.
      #
      # @param relative_path [String] logical Rails path
      # @return [Array<String>] absolute directory paths
      def directory_paths(relative_path)
        paths = configured_paths_for(relative_path)
        paths = [relative_path] if paths.empty?

        paths.map { |path| File.expand_path(path.to_s, root) }.uniq
      end

      # Reads configured Rails paths for a logical key.
      #
      # @param relative_path [String] logical Rails path key from +Rails.application.paths+
      # @return [Array<String>] configured path entries, or an empty array when unavailable
      def configured_paths_for(relative_path)
        Array(app.paths[relative_path]).flat_map do |path|
          Array(path)
        end.compact
      rescue StandardError
        []
      end

      # Counts Ruby files, and JavaScript files for JavaScript paths, under a logical Rails path.
      #
      # @param relative_path [String] logical Rails path
      # @return [Integer] number of matching files under all resolved directories
      def count_files_for(relative_path)
        directory_paths(relative_path).sum do |path|
          next 0 unless Dir.exist?(path)

          count = Dir.glob(File.join(path, '**/*.rb')).size
          count += Dir.glob(File.join(path, '**/*.js')).size if relative_path.include?('javascript')
          count
        end
      end

      # Finds files with the requested extension under all directories for a logical Rails path.
      #
      # @param relative_path [String] logical Rails path
      # @param extension [String] file extension without the leading dot
      # @return [Array<String>] absolute file paths
      def files_for(relative_path, extension:)
        directory_paths(relative_path).flat_map do |path|
          Dir.exist?(path) ? Dir.glob(File.join(path, "**/*.#{extension}")) : []
        end
      end

      # Checks whether a gem appears in the lockfile.
      #
      # @param name [String] gem name
      # @return [Boolean] true when the gem appears in +Gemfile.lock+
      def gem_present?(name)
        lock_path = File.join(root, 'Gemfile.lock')
        return false unless File.exist?(lock_path)

        File.read(lock_path).include?("    #{name} (")
      end
    end
  end
end
