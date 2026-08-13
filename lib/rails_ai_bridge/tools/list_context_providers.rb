# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for listing context providers declared in the registry manifest.
    #
    # Context providers are external services (currently MCP servers) that the
    # bridge can query for project context. This tool reads the
    # +context_providers+ section of the registry manifest and returns a
    # formatted list with each provider's type, endpoint, optional flag, and
    # requested tool specs.
    #
    # @example List all context providers
    #   rails_list_context_providers
    class ListContextProviders < BaseTool
      ENDPOINT_MAX_LENGTH = 80
      SETUP_DOC_PATH = 'docs/skill-registry-guide.md'

      SETUP_MESSAGE = <<~MSG.freeze
        No registry manifest found at `%<path>s`.

        To use context providers, create a registry manifest file.
        See `#{SETUP_DOC_PATH}` for a step-by-step guide.

        Quick start — add `config/rails_ai_bridge/registry.json` to your Rails app:

        ```json
        {
          "version": "1.0.0",
          "packs": {},
          "default_stack": [],
          "context_providers": {}
        }
        ```

        Then configure the registry in `config/initializers/rails_ai_bridge.rb`:

        ```ruby
        RailsAiBridge.configure do |config|
          config.registry.registry_manifest_path = "config/rails_ai_bridge/registry.json"
        end
        ```

        Once configured, add context providers and run `rails ai:skills:list` to verify.
      MSG

      tool_name 'rails_list_context_providers'
      description 'List context providers declared in the registry manifest. ' \
                  'Each provider is an external service (e.g. an MCP server) the bridge ' \
                  'can query for project context. Shows type, endpoint, optional flag, ' \
                  'and requested tool specs. Requires a registry manifest — see docs/skill-registry-guide.md.'

      input_schema(
        properties: {}
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] formatted provider list or a setup/error message
      def self.call(_server_context: nil)
        manifest = load_manifest
        return text_response(format(SETUP_MESSAGE, path: manifest_path)) unless manifest

        text_response(ContextProviderFormatter.new(manifest).format)
      end

      # @api private
      def self.manifest_path
        RailsAiBridge.configuration.registry.registry_manifest_path
      end
      private_class_method :manifest_path

      # @api private
      def self.load_manifest
        path = manifest_path
        return nil unless File.exist?(path)

        Registry::RegistryManifest.from_file(path)
      rescue ArgumentError => error
        Rails.logger&.error { "[rails-ai-bridge] Context provider manifest load failed: #{error.message}" }
        nil
      end
      private_class_method :load_manifest

      # Formats the context providers section of a registry manifest as markdown.
      #
      # Single responsibility: converts manifest data into display-ready markdown.
      # Does not know about MCP, tools, or configuration.
      #
      # @api private
      class ContextProviderFormatter
        include Registry::Truncatable

        # @param manifest [Registry::RegistryManifest]
        def initialize(manifest)
          @manifest = manifest
        end

        # @return [String] markdown string
        def format
          providers = @manifest.context_providers
          return 'No context providers are declared in the registry manifest.' if providers.empty?

          lines = ["# Context Providers (#{providers.length})", '']
          lines << '| Provider | Type | Endpoint | Optional | Tools |'
          lines << '|----------|------|----------|----------|-------|'
          providers.each do |name, provider|
            lines << format_row(name, provider)
          end
          lines.join("\n")
        end

        private

        def format_row(name, provider)
          tools = provider.tools.map { |tool| format_tool(tool) }.join(', ')
          optional = provider.optional? ? 'yes' : 'no'
          "| **#{sanitize_markdown(name)}** | #{sanitize_markdown(provider.type)} | " \
            "#{truncate(sanitize_markdown(provider.endpoint), ENDPOINT_MAX_LENGTH)} | " \
            "#{optional} | #{sanitize_markdown(tools)} |"
        end

        def format_tool(tool)
          return tool.name if tool.simple?

          "#{tool.name} → #{tool.field}"
        end
      end
    end
  end
end
