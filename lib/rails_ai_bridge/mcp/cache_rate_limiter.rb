# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Distributed, fixed-window rate limiter backed by +Rails.cache+ (or any
    # +ActiveSupport::Cache::Store+). Use it when the MCP HTTP endpoint runs
    # behind multiple processes and the default in-memory limiter is insufficient.
    #
    # The limiter relies on the cache's +increment+ operation when available and
    # falls back to read/write for stores that do not support atomic increments.
    class CacheRateLimiter
      # @param max_requests [Integer] allowed hits per window per client IP
      # @param window_seconds [Integer] TTL for each client's counter
      # @param cache [Object, nil] +ActiveSupport::Cache::Store+; defaults to +Rails.cache+
      # @param key_prefix [String] prefix for cache keys
      def initialize(max_requests:, window_seconds:, cache: nil, key_prefix: 'rab:rl')
        @max_requests = max_requests
        @window_seconds = window_seconds.to_i
        @cache = cache
        @key_prefix = key_prefix
      end

      # @param ip [String, nil] client identifier (blank values share the +unknown+ bucket)
      # @return [Boolean] +true+ if the request may proceed
      def allow?(ip)
        store = cache_store
        return true unless store

        key = cache_key(ip)
        count = increment(store, key)
        count <= @max_requests
      end

      private

      def cache_store
        @cache || (defined?(Rails) && Rails.cache)
      end

      def cache_key(ip)
        client = ip.to_s.presence || 'unknown'
        "#{@key_prefix}:#{client}"
      end

      def increment(store, key)
        if store.respond_to?(:increment)
          store.increment(key, 1, expires_in: @window_seconds) || fallback_increment(store, key)
        else
          fallback_increment(store, key)
        end
      rescue StandardError
        fallback_increment(store, key)
      end

      def fallback_increment(store, key)
        if store.respond_to?(:increment)
          store.write(key, 0, expires_in: @window_seconds, unless_exist: true)
          store.increment(key, 1) || (store.read(key).to_i + 1)
        else
          store.write(key, store.read(key).to_i + 1, expires_in: @window_seconds)
          store.read(key).to_i
        end
      rescue StandardError
        1
      end
    end
  end
end
