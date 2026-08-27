# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies the registry manifest is present, valid, and resolvable.
      #
      # Checks (in order):
      # 1. The configured +registry_manifest_path+ exists.
      # 2. The manifest JSON parses successfully.
      # 3. +RegistryManifest.validate!+ passes schema validation.
      # 4. +Registry.build_resolver+ returns a non-nil resolver.
      # 5. The lockfile exists and matches (when +lockfile_path+ is configured).
      #
      # Each failure short-circuits with an actionable fix hint so the user can
      # resolve the first problem before chasing downstream symptoms.
      class RegistryChecker < BaseChecker
        # @param network [Boolean] when true, probe provider reachability after structural checks
        # @return [Doctor::Check] +:pass+, +:warn+, or +:fail+
        def call(network: false)
          return missing_manifest_check unless manifest_path_exists?

          return invalid_json_check unless manifest_parses?

          return validation_failed_check unless manifest_validates?

          resolver = build_resolver
          return resolver_failed_check(resolver) unless resolver

          return lockfile_check if lockfile_configured? && !lockfile_exists?

          return network_reachability_check if network

          new_check(name: 'Registry', status: :pass, message: 'Registry manifest is valid and resolvable', fix: nil)
        end

        private

        def registry_config
          RailsAiBridge.configuration.registry
        end

        def manifest_path
          registry_config.registry_manifest_path
        end

        def manifest_path_exists?
          File.exist?(manifest_path)
        end

        def missing_manifest_check
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Registry manifest not found at `#{manifest_path}`",
            fix: 'Create a registry manifest file — see docs/skill-registry-guide.md'
          )
        end

        def manifest_parses?
          parsed_manifest
          true
        rescue ArgumentError
          false
        end

        def invalid_json_check
          new_check(
            name: 'Registry',
            status: :fail,
            message: "Registry manifest at `#{manifest_path}` contains invalid JSON or could not be read",
            fix: "Fix the JSON syntax in the manifest file — run `ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' #{manifest_path}` to see the parse error"
          )
        end

        def parsed_manifest
          @parsed_manifest ||= RailsAiBridge::Registry::RegistryManifest.from_file(manifest_path)
        end

        def manifest_validates?
          RailsAiBridge::Registry::RegistryManifest.validate!(raw_manifest_hash)
          true
        rescue RailsAiBridge::Registry::RegistryManifest::ValidationError
          false
        end

        def raw_manifest_hash
          JSON.parse(File.read(manifest_path))
        end

        def validation_failed_check
          new_check(
            name: 'Registry',
            status: :fail,
            message: "Registry manifest at `#{manifest_path}` failed schema validation",
            fix: 'Check the manifest structure — see docs/skill-registry-guide.md for the expected schema'
          )
        end

        def build_resolver
          RailsAiBridge::Registry.build_resolver(registry_config)
        end

        def resolver_failed_check(resolver)
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Registry manifest parsed but resolver returned nil#{resolver_reason(resolver)}",
            fix: 'Check that all pack sources are reachable and git is available — see logs for details'
          )
        end

        def resolver_reason(resolver)
          return '' unless resolver.nil?

          ' (manifest missing or pack sources could not be resolved)'
        end

        def lockfile_configured?
          registry_config.lockfile_path
        end

        def lockfile_exists?
          File.exist?(registry_config.lockfile_path)
        end

        def lockfile_check
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Lockfile not found at `#{registry_config.lockfile_path}`",
            fix: 'Run `rails ai:registry:lock` to generate the lockfile, or set lockfile_path to nil to disable verification'
          )
        end

        # @return [Config::ContextProviders] the configured context providers
        def providers_config
          RailsAiBridge.configuration.context_providers
        end

        # Dispatches to the appropriate network check based on config state:
        # disabled → skip, empty manifest → skip, otherwise probe all providers.
        # @return [Check] the network reachability check result
        def network_reachability_check
          return providers_disabled_check unless providers_config.enabled
          return no_providers_check if manifest_context_providers.empty?

          probe_all_providers
        end

        # @return [Hash<String, ContextProviderDefinition>] providers from the manifest
        def manifest_context_providers
          parsed_manifest.context_providers
        end

        # @return [Check] a pass check indicating providers are disabled
        def providers_disabled_check
          new_check(
            name: 'Registry',
            status: :pass,
            message: 'Registry manifest is valid; context providers are disabled',
            fix: nil
          )
        end

        # @return [Check] a pass check indicating no providers are declared
        def no_providers_check
          new_check(
            name: 'Registry',
            status: :pass,
            message: 'Registry manifest is valid and resolvable; no context providers declared',
            fix: nil
          )
        end

        # Probes each declared provider and collects failures (required)
        # and warnings (optional). Returns a fail check if any required
        # provider is unreachable, a warn check if only optional ones are,
        # or a pass check if all are reachable.
        # @return [Check] the aggregated probe result
        def probe_all_providers
          failures = []
          warnings = []

          manifest_context_providers.each do |name, provider|
            result = probe_provider(name, provider)
            next if result.status == :success

            if provider.optional?
              warnings << "#{name}: #{result.error&.message || 'unreachable'}"
            else
              failures << "#{name}: #{result.error&.message || 'unreachable'}"
            end
          end

          return required_failure_check(failures) if failures.any?

          return optional_warning_check(warnings) if warnings.any?

          new_check(
            name: 'Registry',
            status: :pass,
            message: 'Registry manifest is valid; all context providers are reachable',
            fix: nil
          )
        end

        # @param failures [Array<String>] required provider failure messages
        # @return [Check] a fail check listing unreachable required providers
        def required_failure_check(failures)
          new_check(
            name: 'Registry',
            status: :fail,
            message: "Required context provider(s) unreachable: #{failures.join('; ')}",
            fix: 'Check provider endpoint availability and network configuration'
          )
        end

        # @param warnings [Array<String>] optional provider warning messages
        # @return [Check] a warn check listing unreachable optional providers
        def optional_warning_check(warnings)
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Optional context provider(s) unreachable: #{warnings.join('; ')}",
            fix: nil
          )
        end

        # @param name [String] provider name
        # @param provider [ContextProviderDefinition]
        # @return [ContextProviderClient::Result]
        def probe_provider(_name, provider)
          client = build_probe_client(provider)
          client.probe(timeout: providers_config.timeout_seconds)
        rescue RailsAiBridge::Registry::ContextProviderError => error
          RailsAiBridge::Registry::ContextProviderClient::Result.new(
            status: :error,
            content: nil,
            provenance: nil,
            error: error
          )
        rescue StandardError => error
          RailsAiBridge::Registry::ContextProviderClient::Result.new(
            status: :error,
            content: nil,
            provenance: nil,
            error: RailsAiBridge::Registry::ConnectionError.new(
              "probe failed (#{error.class}): #{RailsAiBridge::Registry::MessageSanitizer.sanitize(error.message)}"
            )
          )
        end

        # @param provider [ContextProviderDefinition]
        # @return [ContextProviderClient]
        def build_probe_client(provider)
          timeout = providers_config.timeout_seconds
          policy = RailsAiBridge::Registry::EndpointPolicy.new(
            resolver: Resolv::DNS.new,
            allowed_hosts: providers_config.allowed_hosts,
            allowed_loopback_ports: providers_config.allowed_loopback_ports,
            allow_private_networks: providers_config.allow_private_networks,
            timeout_seconds: timeout,
            max_resolved_addresses: providers_config.max_resolved_addresses
          )
          RailsAiBridge::Registry::ContextProviderClient.new(
            provider: provider,
            policy: policy,
            transport_factory: method(:default_transport_factory),
            auth_resolver: providers_config.auth_resolver,
            timeout_seconds: timeout,
            cleanup_deadline_seconds: [5.0, timeout].min
          )
        end

        # @param uri [URI] the canonical, credential-free provider URI, bound via
        #   the SDK's +url:+ keyword (required by mcp >= 1.3; positional arguments
        #   raise ArgumentError at runtime, swallowed as ConnectionError by the
        #   client boundary). Faraday applies a per-request timeout derived from
        #   +config.context_providers.timeout_seconds+ through the transport's
        #   customizer block. The connection is pinned to the first
        #   policy-validated address via {Registry::PinningHttpAdapter} so DNS
        #   rebinding cannot route the request to an unapproved address.
        # @param addresses [Array<String>] policy-validated IP addresses. The MCP
        #   SDK's MCP::Client::HTTP delegates connection to Faraday; this factory
        #   installs a custom adapter that connects to the approved address while
        #   preserving the original Host header and TLS SNI.
        # @param headers [Hash]
        # @return [Object] MCP transport
        def default_transport_factory(uri, addresses, headers)
          timeout = providers_config.timeout_seconds.to_f
          MCP::Client::HTTP.new(
            url: uri,
            headers: headers,
            max_message_bytes: providers_config.max_response_bytes,
            max_reconnection_wait: timeout
          ) do |faraday|
            options = faraday.options
            options.timeout = timeout
            options.open_timeout = timeout
            faraday.adapter Registry::PinningHttpAdapter, addresses: addresses, original_host: uri.host
          end
        end
      end
    end
  end
end
