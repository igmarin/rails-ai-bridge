# frozen_string_literal: true

require 'cgi'
require 'mcp'

module RailsAiBridge
  # Registers MCP resources and resource templates that expose
  # static introspection data AI clients can read directly.
  module Resources
    # URI pattern for matching model resource URIs (rails://models/{name})
    MODEL_URI_PATTERN = %r{\Arails://models/(.+)\z}

    # URI pattern for matching view resource URIs (rails://views/{path})
    VIEW_URI_PATTERN = %r{\Arails://views/(.+)\z}

    # URI pattern for matching stimulus controller URIs (rails://stimulus/{name})
    STIMULUS_URI_PATTERN = %r{\Arails://stimulus/(.+)\z}

    # Standard MIME type for all JSON resources
    JSON_MIME_TYPE = 'application/json'

    # Error message template for unknown resources
    UNKNOWN_RESOURCE_ERROR = 'Unknown resource: %s'

    # Error message template for missing models
    MODEL_NOT_FOUND_ERROR = "Model '%s' not found"

    # Error message template for missing views
    VIEW_NOT_FOUND_ERROR = "View '%s' not found"

    # Error message template for missing stimulus controllers
    STIMULUS_NOT_FOUND_ERROR = "Stimulus controller '%s' not found"

    # Static resource definitions for built-in MCP resources
    # Maps URIs to metadata including name, description, and context keys
    STATIC_RESOURCES = {
      'rails://bridge/meta' => {
        name: 'Bridge Metadata',
        description: 'Bridge runtime metadata including version, enabled introspectors, tools, ' \
                     'resources, and cache settings',
        mime_type: JSON_MIME_TYPE
      },
      'rails://schema' => {
        name: 'Database Schema',
        description: 'Full database schema including tables, columns, indexes, and foreign keys',
        mime_type: JSON_MIME_TYPE,
        key: :schema
      },
      'rails://routes' => {
        name: 'Application Routes',
        description: 'All routes with HTTP verbs, paths, and controller actions',
        mime_type: JSON_MIME_TYPE,
        key: :routes
      },
      'rails://conventions' => {
        name: 'Conventions & Patterns',
        description: 'Detected architecture patterns, conventions, and directory structure',
        mime_type: JSON_MIME_TYPE,
        key: :conventions
      },
      'rails://gems' => {
        name: 'Notable Gems',
        description: 'Gem dependencies categorized by function with explanations',
        mime_type: JSON_MIME_TYPE,
        key: :gems
      },
      'rails://controllers' => {
        name: 'Controllers',
        description: 'All controllers with actions, filters, strong params, and concerns',
        mime_type: JSON_MIME_TYPE,
        key: :controllers
      },
      'rails://config' => {
        name: 'Application Config',
        description: 'Application configuration including cache, sessions, middleware, and initializers',
        mime_type: JSON_MIME_TYPE,
        key: :config
      },
      'rails://tests' => {
        name: 'Test Infrastructure',
        description: 'Test framework, factories, fixtures, CI, and coverage configuration',
        mime_type: JSON_MIME_TYPE,
        key: :tests
      },
      'rails://migrations' => {
        name: 'Migrations',
        description: 'Migration history, pending migrations, and migration statistics',
        mime_type: JSON_MIME_TYPE,
        key: :migrations
      },
      'rails://engines' => {
        name: 'Mounted Engines',
        description: 'Mounted Rails engines and Rack apps with paths and descriptions',
        mime_type: JSON_MIME_TYPE,
        key: :engines
      },
      'rails://views' => {
        name: 'Views',
        description: 'View layer structure including layouts, templates, partials, helpers, and components',
        mime_type: JSON_MIME_TYPE,
        key: :views
      },
      'rails://stimulus' => {
        name: 'Stimulus Controllers',
        description: 'Stimulus controller inventory with targets, values, actions, outlets, and classes',
        mime_type: JSON_MIME_TYPE,
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
            mime_type: JSON_MIME_TYPE
          ),
          MCP::ResourceTemplate.new(
            uri_template: 'rails://views/{path}',
            name: 'View Details',
            description: 'Detailed information about a specific view template or partial',
            mime_type: JSON_MIME_TYPE
          ),
          MCP::ResourceTemplate.new(
            uri_template: 'rails://stimulus/{name}',
            name: 'Stimulus Controller Details',
            description: 'Detailed information about a specific Stimulus controller',
            mime_type: JSON_MIME_TYPE
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

      # Handles MCP resource read requests with proper error handling.
      # @param params [Hash] request parameters containing :uri
      # @return [Array<Hash>] MCP resource response
      # @raise [RuntimeError] when resource is not found
      def handle_read(params)
        uri = params[:uri]
        payload = resolve_resource_payload(uri)

        raise UNKNOWN_RESOURCE_ERROR % uri unless payload

        json_resource(uri, payload)
      end

      # Resolves the payload for a concrete MCP resource URI.
      # Attempts static resources first, then templated resources.
      # @param uri [String] resource URI requested by the client
      # @return [Object, nil] serializable payload, or +nil+ when no resolver matches
      def resolve_resource_payload(uri)
        read_static_resource(uri) || read_templated_resource(uri)
      end

      # Resolves static resource URIs using predefined resource definitions.
      # Special case for bridge metadata, otherwise uses context sections.
      # @param uri [String] static resource URI
      # @return [Hash, nil] resource data or nil if not found
      def read_static_resource(uri)
        return bridge_metadata if uri == 'rails://bridge/meta'

        definition = resource_definitions[uri]
        return nil unless definition

        fetch_context_section(definition[:key])
      end

      # Resolves templated resource URIs (models, views, stimulus).
      # Tries each template pattern in order until one matches.
      # @param uri [String] templated resource URI
      # @return [Hash, nil] resource data or nil if no pattern matches
      def read_templated_resource(uri)
        read_model_resource(uri) ||
          read_view_template_resource(uri) ||
          read_stimulus_template_resource(uri)
      end

      # Resolves model-specific resource URIs.
      # Extracts model name from URI and fetches from context.
      # @param uri [String] model resource URI (rails://models/{name})
      # @return [Hash, nil] model data or error hash
      def read_model_resource(uri)
        match = uri.match(MODEL_URI_PATTERN)
        return nil unless match

        model_name = CGI.unescape(match[1])
        models = fetch_context_section(:models)
        models[model_name] || { error: MODEL_NOT_FOUND_ERROR % model_name }
      end

      # Resolves view-specific resource URIs.
      # Extracts path from URI and analyzes view file.
      # @param uri [String] view resource URI (rails://views/{path})
      # @return [Hash, nil] view analysis or error hash
      def read_view_template_resource(uri)
        match = uri.match(VIEW_URI_PATTERN)
        return nil unless match

        path = CGI.unescape(match[1])
        read_view_resource(path)
      end

      # Resolves Stimulus controller-specific resource URIs.
      # Extracts controller name from URI and fetches from context.
      # @param uri [String] stimulus resource URI (rails://stimulus/{name})
      # @return [Hash, nil] controller data or error hash
      def read_stimulus_template_resource(uri)
        match = uri.match(STIMULUS_URI_PATTERN)
        return nil unless match

        name = CGI.unescape(match[1])
        read_stimulus_resource(name)
      end

      # Generates bridge metadata including version, configuration, and available resources.
      # Combines static bridge info with dynamic context information.
      # @return [Hash] complete bridge metadata
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

      # Analyzes a view file and returns structured information.
      # Handles security errors and missing files gracefully.
      # @param path [String] relative path to view file
      # @return [Hash] view analysis or error hash
      def read_view_resource(path)
        ViewFileAnalyzer.call(root: Rails.root, relative_path: path)
      rescue SecurityError => error
        { error: error.message }
      rescue Errno::ENOENT
        { error: VIEW_NOT_FOUND_ERROR % path }
      end

      # Fetches Stimulus controller data by name.
      # Uses case-insensitive matching for controller names.
      # @param name [String] controller name to find
      # @return [Hash] controller data or error hash
      def read_stimulus_resource(name)
        data = fetch_context_section(:stimulus)
        controllers = Array(data[:controllers])
        find_controller_by_name(controllers, name) || { error: STIMULUS_NOT_FOUND_ERROR % name }
      end

      # Safely extracts a value from context with fallback.
      # Provides consistent error handling for missing context sections.
      # @param key [Symbol] context section key
      # @return [Hash] context data or empty hash
      def fetch_context_section(key)
        ContextProvider.fetch_section(key) || {}
      end

      # Finds a controller by case-insensitive name match.
      # Encapsulates the case-insensitive comparison logic.
      # @param controllers [Array<Hash>] list of controller entries
      # @param name [String] controller name to find
      # @return [Hash, nil] matching controller or nil
      def find_controller_by_name(controllers, name)
        controllers.find do |entry|
          entry[:name].to_s.casecmp?(name)
        end
      end

      # Formats a JSON MCP resource response payload for the requested URI.
      # Converts any serializable payload to pretty-printed JSON.
      # @param uri [String] resource URI being served
      # @param payload [Object] serializable content returned to the client
      # @return [Array<Hash>] MCP resource response rows
      def json_resource(uri, payload)
        content = JSON.pretty_generate(payload)
        [{ uri: uri, mime_type: JSON_MIME_TYPE, text: content }]
      end
    end
  end
end
