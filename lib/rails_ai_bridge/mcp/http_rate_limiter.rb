# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Sliding-window request counter per client key (typically +request.ip+), in-memory per process.
    class HttpRateLimiter
      # @param max_requests [Integer] allowed hits per window (must be positive)
      # @param window_seconds [Integer] window length in seconds
      # @param clock [Proc, nil] +-> { Float }+ seconds timestamp; defaults to monotonic clock
      def initialize(max_requests:, window_seconds:, clock: nil)
        @max_requests = max_requests
        @window_seconds = window_seconds.to_f
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @mutex = Mutex.new
        @hits = Hash.new { |h, k| h[k] = [] }
      end

      # @param ip [String, nil] client identifier (blank values share the +unknown+ bucket)
      # @return [Boolean] +true+ if the request may proceed
      def allow?(ip)
        key = ip.to_s.presence || 'unknown'
        now = @clock.call
        window_start = now - @window_seconds

        @mutex.synchronize do
          times = @hits[key]
          times.reject! { |t| t < window_start }
          # Drop stale keys so unique IPs that stop requesting do not grow @hits forever.
          @hits.delete(key) if times.empty?

          times = @hits[key]
          return false if times.size >= @max_requests

          times << now
          true
        end
      end
    end
  end
end
