# frozen_string_literal: true

require 'cgi'
require 'mcp'

module RailsAiBridge
  # Registers MCP resources and resource templates that expose
  # static introspection data AI clients can read directly.
  module Resources
    STATIC_RESOURCES = {
      'rails://bridge/meta' => {
        name: 'Bridge Metadata',
        description: 'Bridge runtime metadata including version, enabled introspectors, tools, ' \
                     'resources, and cache settings',
        mime_type: 'application/json'
      },
      'rails://schema' => {
        name: 'Database Schema',
        description: 'Full database schema including tables, columns, indexes, and foreign keys',
        mime_type: 'application/json',
        key: :schema
      },
      'rails://routes' => {
        name: 'Application Routes',
        description: 'All routes with HTTP verbs, paths, and controller actions',
        mime_type: 'application/json',
        key: :routes
      },
      'rails://conventions' => {
        name: 'Conventions & Patterns',
        description: 'Detected architecture patterns, conventions, and directory structure',
        mime_type: 'application/json',
        key: :conventions
      },
      'rails://gems' => {
        name: 'Notable Gems',
        description: 'Gem dependencies categorized by function with explanations',
        mime_type: 'application/json',
        key: :gems
      },
      'rails://controllers' => {
        name: 'Controllers',
        description: 'All controllers with actions, filters, strong params, and concerns',
        mime_type: 'application/json',
        key: :controllers
      },
      'rails://config' => {
        name: 'Application Config',
        description: 'Application configuration including cache, sessions, middleware, and initializers',
        mime_type: 'application/json',
        key: :config
      },
      'rails://tests' => {
        name: 'Test Infrastructure',
        description: 'Test framework, factories, fixtures, CI, and coverage configuration',
        mime_type: 'application/json',
        key: :tests
      },
      'rails://migrations' => {
        name: 'Migrations',
        description: 'Migration history, pending migrations, and migration statistics',
        mime_type: 'application/json',
        key: :migrations
      },
      'rails://engines' => {
        name: 'Mounted Engines',
        description: 'Mounted Rails engines and Rack apps with paths and descriptions',
        mime_type: 'application/json',
        key: :engines
      },
      'rails://views' => {
        name: 'Views',
        description: 'View layer structure including layouts, templates, partials, helpers, and components',
        mime_type: 'application/json',
        key: :views
      },
      'rails://stimulus' => {
        name: 'Stimulus Controllers',
        description: 'Stimulus controller inventory with targets, values, actions, outlets, and classes',
        mime_type: 'application/json',
        key: :stimulus
      }
    }.freeze

    class << self
      # Returns built-in and user-defined MCP resource definitions.
      #
      # @return [Hash{String => Hash}] resource definitions keyed by URI
      def resource_definitions
        STATIC_RESOURCES.merge(RailsAiBridge.configuration.additional_resources)
      end

      # Builds the list of static +MCP::Resource+ objects for all registered URIs.
      # Intended to be passed to +MCP::Server.new(resources: ...)+ at construction time.
      #
      # @return [Array<MCP::Resource>]
      def build_resources
        resource_definitions.map do |uri, meta|
          MCP::Resource.new(
            uri: uri,
            name: meta[:name],
            description: meta[:description],
            mime_type: meta[:mime_type]
          )
        end
      end

      # Builds the list of +MCP::ResourceTemplate+ objects for URI-template resources.
      # Intended to be passed to +MCP::Server.new(resource_templates: ...)+ at construction time.
      #
      # @return [Array<MCP::ResourceTemplate>]
      def build_templates
        [
          MCP::ResourceTemplate.new(
            uri_template: 'rails://models/{name}',
            name: 'Model Details',
            description: 'Detailed information about a specific ActiveRecord model',
            mime_type: 'application/json'
          ),
          MCP::ResourceTemplate.new(
            uri_template: 'rails://views/{path}',
            name: 'View Details',
            description: 'Detailed information about a specific view template or partial',
            mime_type: 'application/json'
          ),
          MCP::ResourceTemplate.new(
            uri_template: 'rails://stimulus/{name}',
            name: 'Stimulus Controller Details',
            description: 'Detailed information about a specific Stimulus controller',
            mime_type: 'application/json'
          )
        ]
      end

      # Registers the +resources/read+ handler on an already-constructed MCP server.
      # Resources and templates must be passed to +MCP::Server.new+ before calling this —
      # see {build_resources} and {build_templates}.
      #
      # @param server [MCP::Server] server instance to register the handler on
      # @return [void]
      def register(server)
        require 'json'

        server.resources_read_handler do |params|
          handle_read(params)
        end
      end

      private

      def handle_read(params)
        uri = params[:uri]
        payload = resolve_resource_payload(uri)

        raise "Unknown resource: #{uri}" unless payload

        json_resource(uri, payload)
      end

      # Resolves the payload for a concrete MCP resource URI.
      #
      # @param uri [String] resource URI requested by the client
      # @return [Object, nil] serializable payload, or +nil+ when no resolver matches
      def resolve_resource_payload(uri)
        read_static_resource(uri) || read_templated_resource(uri)
      end

      def read_static_resource(uri)
        return bridge_metadata if uri == 'rails://bridge/meta'

        definition = resource_definitions[uri]
        return unless definition

        ContextProvider.fetch_section(definition[:key]) || {}
      end

      def read_templated_resource(uri)
        read_model_resource(uri) ||
          read_view_template_resource(uri) ||
          read_stimulus_template_resource(uri)
      end

      def read_model_resource(uri)
        match = uri.match(%r{\Arails://models/(.+)\z})
        return unless match

        model_name = CGI.unescape(match[1])
        models = ContextProvider.fetch_section(:models) || {}
        models[model_name] || { error: "Model '#{model_name}' not found" }
      end

      def read_view_template_resource(uri)
        match = uri.match(%r{\Arails://views/(.+)\z})
        return unless match

        path = CGI.unescape(match[1])
        read_view_resource(path)
      end

      def read_stimulus_template_resource(uri)
        match = uri.match(%r{\Arails://stimulus/(.+)\z})
        return unless match

        name = CGI.unescape(match[1])
        read_stimulus_resource(name)
      end

      def bridge_metadata
        context = ContextProvider.fetch || {}

        {
          bridge_version: RailsAiBridge::VERSION,
          server_name: RailsAiBridge.configuration.server_name,
          server_version: RailsAiBridge.configuration.server_version,
          context_mode: RailsAiBridge.configuration.context_mode,
          cache_ttl: RailsAiBridge.configuration.cache_ttl,
          app_name: context[:app_name],
          generated_at: context[:generated_at],
          enabled_introspectors: RailsAiBridge.configuration.introspectors.map(&:to_s),
          available_tools: (RailsAiBridge::Server::TOOLS + RailsAiBridge.configuration.additional_tools).map(&:tool_name).sort,
          available_resources: resource_definitions.keys.sort,
          available_sections: context.keys.grep(Symbol).map(&:to_s).sort
        }
      end

      def read_view_resource(path)
        ViewFileAnalyzer.call(root: Rails.root, relative_path: path)
      rescue SecurityError => error
        { error: error.message }
      rescue Errno::ENOENT
        { error: "View '#{path}' not found" }
      end

      def read_stimulus_resource(name)
        data = ContextProvider.fetch_section(:stimulus) || {}
        controllers = Array(data[:controllers])
        controllers.find do |entry|
          entry[:name].to_s.casecmp?(name)
        end || { error: "Stimulus controller '#{name}' not found" }
      end

      # Formats a JSON MCP resource response payload for the requested URI.
      #
      # @param uri [String] resource URI being served
      # @param payload [Object] serializable content returned to the client
      # @return [Array<Hash>] MCP resource response rows
      def json_resource(uri, payload)
        content = JSON.pretty_generate(payload)
        [{ uri: uri, mime_type: 'application/json', text: content }]
      end
    end
  end
end
