# frozen_string_literal: true

module RailsAiBridge
  class Introspector
    # Runs multiple introspectors concurrently using a thread pool.
    #
    # Requires +concurrent-ruby+ (already a transitive dependency of Rails).
    # Falls back gracefully when the gem is unavailable — callers should
    # check {.available?} before using this runner.
    #
    # Each introspector is executed in its own thread. Errors are captured
    # per-introspector and returned as +{ error: message }+ hashes, matching
    # the convention used by {Introspector#call}.
    class ParallelRunner
      POOL_SIZE = 4

      class << self
        # Runs +introspectors+ concurrently and returns a Hash of results.
        #
        # @param introspectors [Hash{Symbol => Class}] name → introspector class pairs
        # @param app [Rails::Application]
        # @return [Hash{Symbol => Object}] introspection results keyed by name
        def call(introspectors, app)
          return {} if introspectors.empty?

          pool = Concurrent::FixedThreadPool.new([introspectors.size, POOL_SIZE].min)
          futures = schedule_futures(introspectors, app, pool)
          collect_results(futures)
        ensure
          pool&.shutdown
          pool&.wait_for_termination(10)
        end

        # Whether +concurrent-ruby+ is available.
        #
        # @return [Boolean]
        def available?
          defined?(Concurrent::Future) == 'constant'
        end

        private

        def schedule_futures(introspectors, app, pool)
          introspectors.map do |name, klass|
            future = Concurrent::Future.execute(executor: pool) do
              klass.new(app).call
            end
            [name, future]
          end
        end

        def collect_results(futures)
          futures.each_with_object({}) do |(name, future), results|
            results[name] = resolve_future(name, future)
          end
        end

        def resolve_future(name, future)
          future.value!
        rescue StandardError => error
          Rails.logger.warn("[rails-ai-bridge] #{name} introspection failed: #{error.message}")
          { error: error.message }
        end
      end
    end
  end
end
