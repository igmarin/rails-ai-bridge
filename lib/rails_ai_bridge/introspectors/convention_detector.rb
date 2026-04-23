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

      # @return [Hash] detected conventions and patterns
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

      def detect_patterns
        patterns = []

        # Check for common Rails patterns in model files
        model_dir = File.join(root, 'app/models')
        if Dir.exist?(model_dir)
          model_files = Dir.glob(File.join(model_dir, '**/*.rb'))
          content = model_files.first(50).map do |f|
            File.read(f)
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
          full_path = File.join(root, dir)
          next unless Dir.exist?(full_path)

          count = Dir.glob(File.join(full_path, '**/*.rb')).size
          count += Dir.glob(File.join(full_path, '**/*.js')).size if dir.include?('javascript')

          hash[dir] = count if count.positive?
        end
      end

      def detect_config_files
        configs = %w[
          config/database.yml config/credentials.yml.enc
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

      def dir_exists?(relative_path)
        Dir.exist?(File.join(root, relative_path))
      end

      def file_exists?(relative_path)
        File.exist?(File.join(root, relative_path))
      end

      def gem_present?(name)
        lock_path = File.join(root, 'Gemfile.lock')
        return false unless File.exist?(lock_path)

        File.read(lock_path).include?("    #{name} (")
      end
    end
  end
end
