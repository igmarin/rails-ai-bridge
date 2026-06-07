# frozen_string_literal: true

require 'json'
require 'yaml'

module RailsAiBridge
  # Registry resolution system for skill packs.
  #
  # Provides priority-based loading of skill packs from git repositories,
  # deprecation redirect handling, and framework auto-detection.
  #
  # @see Registry::RegistryManifest
  # @see Registry::PackDefinition
  # @see Registry::TileManifest
  # @see Registry::FrontmatterParser
  # @see Registry::PackDetector
  # @see Registry::GitRunner
  # @see Registry::DefaultGitRunner
  # @see Registry::SkillSourceResolver
  # @see Registry::PackResolver
  # @see Registry::Resolver
  # @see Registry::LoadedPack
  # @see Registry::ResolvedSkill
  # @see Registry::SkillSummary
  module Registry
    # Module-level resolver cache (one per process, lazy-initialized on first use).
    #
    # @api private
    @resolver_cache = nil
    @resolver_cache_mutex = Mutex.new

    # Returns the module-level {ResolverCache} instance, creating it on first call.
    #
    # @api private
    def self.resolver_cache
      @resolver_cache_mutex.synchronize do
        @resolver_cache ||= ResolverCache.new
      end
    end

    # Discards the cached resolver so the next {build_resolver} call rebuilds from disk.
    #
    # Call this after clearing the git cache or modifying the registry manifest at runtime.
    #
    # @return [void]
    def self.invalidate_resolver_cache!
      @resolver_cache_mutex.synchronize { @resolver_cache&.invalidate! }
    end

    # Builds (or returns a cached) {Resolver} from the current {Config::Registry}.
    #
    # The first call for a given TTL window loads the manifest from disk, wires the
    # {SkillSourceResolver} and {PackResolver} pipeline, and caches the result.
    # Subsequent calls within the TTL window return the same resolver without I/O.
    #
    # Returns +nil+ when the registry manifest file does not exist, allowing callers
    # to surface a helpful setup message rather than raising. A nil result is never
    # cached — the next call will retry.
    #
    # @param config [RailsAiBridge::Config::Registry] registry configuration
    # @return [Resolver, nil] wired resolver, or nil if manifest file is missing
    def self.build_resolver(config = RailsAiBridge.configuration.registry)
      resolver_cache.fetch(config) { build_resolver_uncached(config) }
    end

    # @api private
    def self.build_resolver_uncached(config)
      manifest_path = config.registry_manifest_path
      return nil unless File.exist?(manifest_path)

      manifest = RegistryManifest.from_file(manifest_path)
      source_resolver = SkillSourceResolver.new(config.skill_cache_dir)
      pack_resolver = PackResolver.new(source_resolver)

      pack_resolver.resolve(
        manifest,
        config.skill_packs,
        config.local_registry_paths.empty? ? nil : config.local_registry_paths
      )
    end
    private_class_method :build_resolver_uncached
  end
end
