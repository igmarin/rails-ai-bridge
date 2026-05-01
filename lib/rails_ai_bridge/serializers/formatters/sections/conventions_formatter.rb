# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the App Conventions & Architecture section.
      #
      # @see Formatters::Providers::SectionFormatter
      class ConventionsFormatter < SectionFormatter
        section :conventions

        ARCH_LABELS = {
          'api_only' => 'API-only mode (no views/assets)',
          'hotwire' => 'Hotwire (Turbo + Stimulus)',
          'graphql' => 'GraphQL API (app/graphql/)',
          'grape_api' => 'Grape API framework (app/api/)',
          'service_objects' => 'Service objects pattern (app/services/)',
          'form_objects' => 'Form objects (app/forms/)',
          'query_objects' => 'Query objects (app/queries/)',
          'presenters' => 'Presenters/Decorators',
          'view_components' => 'ViewComponent (app/components/)',
          'stimulus' => 'Stimulus controllers (app/javascript/controllers/)',
          'importmaps' => 'Import maps (no JS bundler)',
          'docker' => 'Dockerized',
          'kamal' => 'Kamal deployment',
          'ci_github_actions' => 'GitHub Actions CI'
        }.freeze

        PATTERN_LABELS = {
          'sti' => 'Single Table Inheritance (STI)',
          'polymorphic' => 'Polymorphic associations',
          'soft_delete' => 'Soft deletes (paranoia/discard)',
          'versioning' => 'Model versioning/auditing',
          'state_machine' => 'State machines (AASM/workflow)',
          'multi_tenancy' => 'Multi-tenancy',
          'searchable' => 'Full-text search (Searchkick/pg_search/Ransack)',
          'taggable' => 'Tagging',
          'sluggable' => 'Friendly URLs/slugs',
          'nested_set' => 'Tree/nested set structures'
        }.freeze

        private

        def render(data)
          config_files = ContextSummary.safe_config_files(data[:config_files])
          return unless data[:architecture]&.any? || data[:patterns]&.any? ||
                        data[:directory_structure]&.any? || config_files.any?

          lines = ['## App Conventions & Architecture', '']

          # Architecture
          if data[:architecture]&.any?
            lines << '### Architecture'
            data[:architecture].each { |a| lines << "- #{humanize_arch(a)}" }
          end

          # Patterns
          if data[:patterns]&.any?
            lines << '' << '### Detected patterns'
            data[:patterns].each { |p| lines << "- #{humanize_pattern(p)}" }
          end

          # Directory structure
          if data[:directory_structure]&.any?
            lines << '' << '### Directory structure'
            data[:directory_structure].sort_by { |k, _| k }.each do |dir, count|
              lines << "- `#{dir}/` → #{count} files"
            end
          end

          # Config files
          if config_files.any?
            lines << '' << '### Config files present'
            config_files.each { |f| lines << "- `#{f}`" }
          end

          lines.join("\n")
        end

        def humanize_arch(key)
          ARCH_LABELS[key] || key.humanize
        end

        def humanize_pattern(key)
          PATTERN_LABELS[key] || key.humanize
        end
      end
    end
  end
end
