# frozen_string_literal: true

module RailsAiBridge
  class Fingerprinter
    # Caches fingerprint snapshots to avoid redundant filesystem walks.
    #
    # Every +ContextProvider.fetch+ triggers a +Fingerprinter.snapshot+ call
    # that walks 10+ directories reading mtimes. This class caches the result
    # for a short TTL (default 5s), so rapid MCP tool calls reuse the same
    # snapshot without repeated I/O.
    #
    # Thread-safe via +Mutex+.
    class CachedSnapshot
      @cache = {}
      @mutex = Mutex.new
      @snapshot_ttl = 5

      class << self
        # @return [Integer] seconds to cache a fingerprint snapshot
        attr_accessor :snapshot_ttl

        # Returns the fingerprint for +app+, reusing a cached value when
        # the snapshot TTL has not expired.
        #
        # @param app [Rails::Application]
        # @return [String] SHA256 hex digest
        def fetch(app)
          @mutex.synchronize do
            key = app.object_id
            entry = @cache[key]

            if entry && ttl_valid?(entry)
              entry[:fingerprint]
            else
              compute_and_cache(app, key)
            end
          end
        end

        # Clears all cached snapshots.
        #
        # @return [void]
        def reset!
          @mutex = Mutex.new
          @cache = {}
        end

        # Invalidates the cached snapshot for a specific app, forcing
        # re-computation on the next +fetch+.
        #
        # @param app [Rails::Application]
        # @return [void]
        def invalidate!(app)
          @mutex.synchronize { @cache.delete(app.object_id) }
        end

        private

        def compute_and_cache(app, key)
          fingerprint = Fingerprinter.snapshot(app)
          @cache[key] = { fingerprint: fingerprint, fetched_at: monotonic_now }
          fingerprint
        end

        def ttl_valid?(entry)
          (monotonic_now - entry[:fetched_at]) < effective_ttl
        end

        def effective_ttl
          RailsAiBridge.configuration.snapshot_ttl
        rescue NoMethodError
          @snapshot_ttl
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
