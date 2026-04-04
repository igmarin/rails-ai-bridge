# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool exposing detected architecture, patterns, directory layout, and config files.
    class GetConventions < BaseTool
      tool_name "rails_get_conventions"
      description "Detect architectural patterns and conventions used in this Rails app. Returns info about architecture style (API-only, Hotwire, GraphQL), design patterns (service objects, STI, polymorphism), directory structure, and config files present."

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] markdown convention summary or an error message
      def self.call(server_context: nil)
        conventions = cached_section(:conventions)
        return text_response("Convention detection not available. Add :conventions to introspectors.") unless conventions
        return text_response("Convention detection failed: #{conventions[:error]}") if conventions[:error]

        formatter = ResponseFormatter.new(conventions)
        text_response(formatter.format)
      end

      # @private
      # Formats +:conventions+ introspection hash as markdown for {GetConventions}.
      class ResponseFormatter
        def initialize(conventions)
          @conventions = conventions
        end

        def format
          lines = [ "# App Conventions & Architecture", "" ]

          # Architecture
          if @conventions[:architecture]&.any?
            lines << "## Architecture"
            @conventions[:architecture].each { |a| lines << "- #{humanize_arch(a)}" }
          end

          # Patterns
          if @conventions[:patterns]&.any?
            lines << "" << "## Detected patterns"
            @conventions[:patterns].each { |p| lines << "- #{humanize_pattern(p)}" }
          end

          # Directory structure
          if @conventions[:directory_structure]&.any?
            lines << "" << "## Directory structure"
            @conventions[:directory_structure].sort_by { |k, _| k }.each do |dir, count|
              lines << "- `#{dir}/` → #{count} files"
            end
          end

          # Config files
          if @conventions[:config_files]&.any?
            lines << "" << "## Config files present"
            @conventions[:config_files].each { |f| lines << "- `#{f}`" }
          end

          lines.join("\n")
        end

        private

        def humanize_arch(key)
          ARCH_LABELS[key] || key.humanize
        end

        def humanize_pattern(key)
          PATTERN_LABELS[key] || key.humanize
        end

        ARCH_LABELS = {
          "api_only" => "API-only mode (no views/assets)",
          "hotwire" => "Hotwire (Turbo + Stimulus)",
          "graphql" => "GraphQL API (app/graphql/)",
          "grape_api" => "Grape API framework (app/api/)",
          "service_objects" => "Service objects pattern (app/services/)",
          "form_objects" => "Form objects (app/forms/)",
          "query_objects" => "Query objects (app/queries/)",
          "presenters" => "Presenters/Decorators",
          "view_components" => "ViewComponent (app/components/)",
          "stimulus" => "Stimulus controllers (app/javascript/controllers/)",
          "importmaps" => "Import maps (no JS bundler)",
          "docker" => "Dockerized",
          "kamal" => "Kamal deployment",
          "ci_github_actions" => "GitHub Actions CI"
        }.freeze

        PATTERN_LABELS = {
          "sti" => "Single Table Inheritance (STI)",
          "polymorphic" => "Polymorphic associations",
          "soft_delete" => "Soft deletes (paranoia/discard)",
          "versioning" => "Model versioning/auditing",
          "state_machine" => "State machines (AASM/workflow)",
          "multi_tenancy" => "Multi-tenancy",
          "searchable" => "Full-text search (Searchkick/pg_search/Ransack)",
          "taggable" => "Tagging",
          "sluggable" => "Friendly URLs/slugs",
          "nested_set" => "Tree/nested set structures"
        }.freeze
      end
    end
  end
end
