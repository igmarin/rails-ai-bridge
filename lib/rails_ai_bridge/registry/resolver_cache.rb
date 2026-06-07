# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Thread-safe resolver cache with configurable TTL.
    #
    # Single responsibility: holds one resolved +Resolver+ and tracks its age.
    # Callers call {#fetch} with a build block; the cache returns the warm
    # resolver when the TTL has not expired, or calls the block to rebuild.
    #
    # A nil result from the block (manifest missing) is never cached so the
    # next call will try again — useful during initial setup.
    #
    # @example
    #   cache = ResolverCache.new
    #   resolver = cache.fetch(config) { Registry.build_resolver_uncached(config) }
    class ResolverCache
      # @param monotonic_clock [#call] injectable clock for testing; defaults to Process.clock_gettime
      def initialize(monotonic_clock: method(:default_clock))
        @mutex   = Mutex.new
        @clock   = monotonic_clock
        @entry   = nil
        @built_at = nil
      end

      # Return a warm cached resolver or build a new one.
      #
      # @param config [Config::Registry] current registry configuration
      # @yieldreturn [Registry::Resolver, nil] freshly built resolver, or nil if manifest is missing
      # @return [Registry::Resolver, nil]
      def fetch(config, &build_block)
        @mutex.synchronize do
          if @entry && !expired?(config)
            @entry
          else
            result = build_block.call
            if result
              @entry    = result
              @built_at = @clock.call
            end
            result
          end
        end
      end

      # Discard the cached resolver; the next {#fetch} call will rebuild.
      # @return [void]
      def invalidate!
        @mutex.synchronize do
          @entry    = nil
          @built_at = nil
        end
      end

      private

      def expired?(config)
        return true unless @built_at

        age = @clock.call - @built_at
        age >= config.resolver_ttl
      end

      def default_clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
