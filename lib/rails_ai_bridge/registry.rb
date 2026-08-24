# frozen_string_literal: true

require 'json'
require 'yaml'

# Load registry sub-files in dependency order.
# Zeitwerk manages the lib/ tree lazily, but these files reference sibling
# constants at method-invocation time (not just at parse time), so Zeitwerk
# cannot intercept them before the first NameError fires. Explicit requires
# here guarantee the full dependency graph is loaded when Registry is first used.
require_relative 'registry/truncatable'
require_relative 'registry/frontmatter_parser'
require_relative 'registry/pack_definition'
require_relative 'registry/context_tool_spec'
require_relative 'registry/context_provider_definition'
require_relative 'registry/pack_detector'
require_relative 'registry/registry_manifest'
require_relative 'registry/tile_manifest'
require_relative 'registry/resolver'
require_relative 'registry/source_parser'
require_relative 'registry/skill_source_resolver'
require_relative 'registry/pack_resolver'
require_relative 'registry/lockfile'
require_relative 'registry/resolver_cache'
require_relative 'registry/rake_presenter'

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
    # Thread-local key for the request-scoped resolver.
    #
    # @api private
    REQUEST_RESOLVER_KEY = :rails_ai_bridge_request_resolver

    # Sentinel stored in the thread-local to mark the request scope as active
    # before the first resolver is built. The non-nil sentinel allows
    # +request_active?+ (which checks +Thread.current.key?+) to distinguish
    # an active, not-yet-built scope from an inactive one. Both
    # +request_resolver?+ and +request_resolver+ treat the sentinel the same
    # as +nil+: no resolver has been built yet.
    #
    # @api private
    REQUEST_ACTIVE_SENTINEL = Object.new.freeze
    private_constant :REQUEST_ACTIVE_SENTINEL

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

    # Wraps a block in a request scope so that {build_resolver} is called at most
    # once per request cycle. The first {build_resolver} call within the block
    # stores the result in a thread-local; subsequent calls return the same
    # resolver without touching the TTL cache. The thread-local is always cleared
    # when the block exits, even on error.
    #
    # @yield block to execute within the request scope
    # @return [Object] the block result
    def self.with_request_resolver
      previous = Thread.current[REQUEST_RESOLVER_KEY]
      Thread.current[REQUEST_RESOLVER_KEY] = REQUEST_ACTIVE_SENTINEL
      yield
    ensure
      Thread.current[REQUEST_RESOLVER_KEY] = previous
    end

    # Clears the request-scoped resolver for the current thread, if any.
    #
    # @return [void]
    def self.clear_request_resolver!
      Thread.current[REQUEST_RESOLVER_KEY] = nil
    end

    # Builds (or returns a cached) {Resolver} from the current {Config::Registry}.
    #
    # The first call for a given TTL window loads the manifest from disk, wires the
    # {SkillSourceResolver} and {PackResolver} pipeline, and caches the result.
    # Subsequent calls within the TTL window return the same resolver without I/O.
    #
    # When inside a {with_request_resolver} block, the first successful build is
    # memoized for the remainder of the request so multiple tool calls in the same
    # request cycle share a single resolver without risking a mid-request rebuild.
    #
    # Returns +nil+ when the registry manifest file does not exist, allowing callers
    # to surface a helpful setup message rather than raising. A nil result is never
    # cached — the next call will retry.
    #
    # @param config [RailsAiBridge::Config::Registry] registry configuration
    # @return [Resolver, nil] wired resolver, or nil if manifest file is missing
    def self.build_resolver(config = RailsAiBridge.configuration.registry)
      return request_resolver if request_resolver?

      resolver = resolver_cache.fetch(config) { build_resolver_uncached(config) }
      store_request_resolver(resolver) if request_active?
      resolver
    end

    # @api private
    def self.request_resolver?
      value = Thread.current[REQUEST_RESOLVER_KEY]
      !value.nil? && !value.equal?(REQUEST_ACTIVE_SENTINEL)
    end
    private_class_method :request_resolver?

    # @api private
    def self.request_resolver
      value = Thread.current[REQUEST_RESOLVER_KEY]
      value.equal?(REQUEST_ACTIVE_SENTINEL) ? nil : value
    end
    private_class_method :request_resolver

    # @api private
    def self.request_active?
      Thread.current.key?(REQUEST_RESOLVER_KEY)
    end
    private_class_method :request_active?

    # @api private
    def self.store_request_resolver(resolver)
      Thread.current[REQUEST_RESOLVER_KEY] = resolver if resolver
    end
    private_class_method :store_request_resolver

    # Writes a lockfile containing the current HEAD commit SHA for every pack in
    # the registry manifest.
    #
    # @param config [RailsAiBridge::Config::Registry] registry configuration
    # @return [void]
    # @raise [ArgumentError] when the manifest file does not exist
    def self.write_lockfile(config = RailsAiBridge.configuration.registry)
      manifest_path = config.registry_manifest_path
      raise ArgumentError, "Registry manifest not found at #{manifest_path}" unless File.exist?(manifest_path)

      manifest = RegistryManifest.from_file(manifest_path)
      git_runner = DefaultGitRunner.new(timeout: config.git_timeout)
      source_resolver = SkillSourceResolver.new(config.skill_cache_dir, git_runner, pull_ttl: config.git_pull_ttl)

      Lockfile.write(config.lockfile_path, manifest, source_resolver)
    end

    # @api private
    def self.build_resolver_uncached(config)
      manifest_path = config.registry_manifest_path
      return nil unless File.exist?(manifest_path)

      manifest = RegistryManifest.from_file(manifest_path)
      git_runner = Registry::DefaultGitRunner.new(timeout: config.git_timeout)
      source_resolver = SkillSourceResolver.new(config.skill_cache_dir, git_runner, pull_ttl: config.git_pull_ttl)
      pack_resolver = PackResolver.new(source_resolver)

      pack_resolver.resolve(
        manifest,
        config.skill_packs,
        config.local_registry_paths.empty? ? nil : config.local_registry_paths
      )
    rescue SkillSourceResolver::ResolutionError, ArgumentError => error
      Rails.logger&.error { "[rails-ai-bridge] Registry build failed: #{error.message}" }
      nil
    end
    private_class_method :build_resolver_uncached
  end
end
