# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Shared builder for creating Resolver instances from configuration.
    # Used by both Rake tasks and MCP tools to avoid code duplication.
    module ResolverBuilder
      # Builds a registry resolver from the current configuration.
      #
      # @param config [RailsAiBridge::Configuration] the bridge configuration
      # @return [RailsAiBridge::Registry::Resolver, nil] resolver instance or nil if configuration is invalid
      def build_resolver(config)
        return nil unless config.registry.registry_manifest_path

        manifest_path = config.registry.registry_manifest_path
        return nil unless File.exist?(manifest_path)

        manifest = RegistryManifest.from_file(manifest_path)
        source_resolver = SkillSourceResolver.new(config.registry.skill_cache_dir)
        pack_resolver = PackResolver.new(source_resolver)

        pack_resolver.resolve(
          manifest,
          config.registry.skill_packs,
          config.registry.local_registry_paths
        )
      rescue StandardError => error
        warn "[rails-ai-bridge] Error building registry resolver: #{error.message}"
        warn error.backtrace.first(5).join("\n") if error.backtrace
        nil
      end
    end
  end
end
