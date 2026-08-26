# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for fetching context from declared external providers.
    #
    # Calls the {Registry::ContextAggregator} to fetch and map results from
    # providers declared in the registry manifest. Providers are disabled by
    # default; this tool returns a setup message when +context_providers.enabled+
    # is false. It is separate from the local {Tools::GetContext} tool and does
    # not alter its behavior.
    #
    # @example Fetch all providers
    #   rails_get_provider_context
    #
    # @example Fetch a single provider
    #   rails_get_provider_context(provider: "billing")
    class GetProviderContext < BaseTool
      tool_name 'rails_get_provider_context'
      description 'Fetch context from declared external MCP providers. ' \
                  'Providers must be enabled and allowlisted in configuration. ' \
                  'Without a provider argument, all declared providers are fetched. ' \
                  'With a provider name, only that provider is fetched. ' \
                  'This tool is separate from rails_get_context (local in-process composite).'

      input_schema(
        properties: {
          provider: {
            type: 'string',
            description: 'Optional provider name from the registry manifest. ' \
                         'When omitted, all declared providers are fetched.'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: false, open_world_hint: true)

      DISABLED_MESSAGE = <<~MSG
        Context providers are disabled. To enable outbound provider access:

        ```ruby
        RailsAiBridge.configure do |config|
          config.context_providers.enabled = true
          config.context_providers.allowed_hosts = ['context.example.com']
        end
        ```

        See `docs/v5/context-providers-design.md` for configuration and security details.
      MSG

      NO_MANIFEST_MESSAGE = <<~MSG
        No registry manifest found. Create `config/rails_ai_bridge/registry.json` with
        a `context_providers` section to declare external providers.

        See `docs/skill-registry-guide.md` for a step-by-step guide.
      MSG

      NO_PROVIDERS_MESSAGE = 'No context providers are declared in the registry manifest.'

      # @param provider [String, nil] optional provider name from the manifest
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] formatted provider context or a setup/error message
      def self.call(provider: nil, _server_context: nil)
        return text_response(DISABLED_MESSAGE) unless providers_config.enabled

        manifest = load_manifest
        return text_response(NO_MANIFEST_MESSAGE) unless manifest

        return text_response(NO_PROVIDERS_MESSAGE) if manifest.context_providers.empty?

        return text_response("Provider `#{provider}` not found in the registry manifest.") if provider && !manifest.context_providers.key?(provider)

        aggregator = build_aggregator(manifest)
        result = provider ? aggregator.fetch_one(provider) : aggregator.fetch_all
        text_response(format_result(result, provider_name: provider))
      end

      # @return [RailsAiBridge::Config::ContextProviders]
      def self.providers_config
        RailsAiBridge.configuration.context_providers
      end
      private_class_method :providers_config

      # @return [RegistryManifest, nil]
      def self.load_manifest
        path = RailsAiBridge.configuration.registry.registry_manifest_path
        return nil unless path && File.exist?(path)

        Registry::RegistryManifest.from_file(path)
      rescue ArgumentError, JSON::ParserError => error
        Rails.logger&.error { "[rails-ai-bridge] Manifest load failed: #{error.message}" }
        nil
      end
      private_class_method :load_manifest

      # @param manifest [RegistryManifest]
      # @return [Registry::ContextAggregator]
      def self.build_aggregator(manifest)
        Registry::ContextAggregator.new(
          manifest: manifest,
          config: providers_config,
          client_factory: method(:build_client),
          scope: Registry::ProviderRequestScope.new
        )
      end
      private_class_method :build_aggregator

      # @param provider_def [Registry::ContextProviderDefinition]
      # @return [Registry::ContextProviderClient]
      def self.build_client(provider_def)
        Registry::ContextProviderClient.new(
          provider: provider_def,
          policy: Registry::EndpointPolicy.new(
            resolver: Resolv::DNS.new,
            allowed_hosts: providers_config.allowed_hosts,
            allowed_loopback_ports: providers_config.allowed_loopback_ports,
            allow_private_networks: providers_config.allow_private_networks
          ),
          transport_factory: method(:default_transport_factory),
          auth_resolver: providers_config.auth_resolver
        )
      end
      private_class_method :build_client

      # @param uri [URI]
      # @param _addresses [Array<String>] policy-validated IP addresses (see design doc INV-6)
      # @param headers [Hash]
      # @return [Object] MCP transport
      def self.default_transport_factory(uri, _addresses, headers)
        MCP::Client::HTTP.new(uri, headers: headers)
      end
      private_class_method :default_transport_factory

      # Formats an aggregate result as markdown.
      #
      # @param result [Registry::ContextAggregator::AggregateResult]
      # @param provider_name [String, nil]
      # @return [String] markdown body
      def self.format_result(result, provider_name: nil)
        formatter = ResultFormatter.new(result, provider_name:)
        formatter.format
      end
      private_class_method :format_result

      # Formats aggregate results as markdown for MCP response.
      #
      # @api private
      class ResultFormatter
        STATUS_LABELS = {
          success: 'All OK',
          partial_failure: 'Partial Failure',
          error: 'Failed'
        }.freeze

        # @param result [Registry::ContextAggregator::AggregateResult]
        # @param provider_name [String, nil]
        def initialize(result, provider_name: nil)
          @result = result
          @provider_name = provider_name
        end

        # @return [String] markdown body
        def format
          lines = []
          lines << header
          lines << ''

          if @result.results.any?
            @result.results.each do |name, data|
              lines << "## #{name}"
              lines << ''
              lines << format_data(data)
              lines << ''
              lines << "_Source: #{name}_"
              lines << ''
            end
          end

          if @result.failures.any?
            lines << '## Failures'
            lines << ''
            @result.failures.each do |error|
              provider = error.respond_to?(:provider_name) ? error.provider_name : 'unknown'
              lines << "- **#{provider}** (#{error.class.name.demodulize}): #{error.message}"
            end
            lines << ''
          end

          lines << "_Elapsed: #{@result.elapsed_ms}ms_"
          lines.join("\n")
        end

        private

        def header
          if @provider_name
            status_label = @result.error? ? 'FAILED' : 'OK'
            "# Provider Context: #{@provider_name} (#{status_label})"
          else
            status = STATUS_LABELS.fetch(@result.status, 'Unknown')
            "# Provider Context (#{status})"
          end
        end

        def format_data(data)
          case data
          when String
            data
          when Hash
            data.map { |key, value| "- **#{key}**: #{format_value(value)}" }.join("\n")
          when Array
            data.map { |item| "- #{format_value(item)}" }.join("\n")
          else
            data.to_s
          end
        end

        def format_value(value)
          if value.is_a?(Hash) || value.is_a?(Array)
            JSON.pretty_generate(value)
          else
            value.to_s
          end
        end
      end
    end
  end
end
