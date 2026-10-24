# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Sliding-window request counter per client key (typically +request.ip+), in-memory per process.
    # Keeps up to 10,000 active clients; new clients fail closed when capacity is full.
    class HttpRateLimiter
      MAX_CLIENTS = 10_000
      private_constant :MAX_CLIENTS

      # @param max_requests [Integer] allowed hits per window (must be positive)
      # @param window_seconds [Integer] window length in seconds
      # @param clock [Proc, nil] +-> { Float }+ seconds timestamp; defaults to monotonic clock
      def initialize(max_requests:, window_seconds:, clock: nil)
        @max_requests = max_requests
        @window_seconds = window_seconds.to_f
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @mutex = Mutex.new
        @hits = {}
      end

      # @param ip [String, nil] client identifier (blank values share the +unknown+ bucket)
      # @return [Boolean] +true+ if the request may proceed
      def allow?(ip)
        key = ip.to_s.presence || 'unknown'
        @mutex.synchronize do
          now = @clock.call
          window_start = now - @window_seconds
          prune_expired(window_start)
          return false if !@hits.key?(key) && @hits.size >= MAX_CLIENTS

          times = @hits[key] || []
          times.reject! { |time| time < window_start }
          return false if times.size >= @max_requests

          times << now
          # Keep buckets ordered by their latest accepted hit for expiration.
          @hits.delete(key)
          @hits[key] = times
          true
        end
      end

      private

      def prune_expired(window_start)
        while (oldest = @hits.first)
          break if oldest.last.last >= window_start

          @hits.shift
        end
      end
    end
  end
end
