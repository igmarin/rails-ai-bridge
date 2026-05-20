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

        def available?
          return false unless defined?(Concurrent::Future) == 'constant'

          # If ActiveRecord is defined and has a connection pool size of 1 or less,
          # running in parallel is highly likely to deadlock or block in transactional
          # tests or single-connection environments.
          if defined?(ActiveRecord::Base)
            pool_size = begin
              ActiveRecord::Base.connection_pool.size
            rescue StandardError
              nil
            end
            return false if pool_size && pool_size <= 1
          end

          true
        end

        private

        def schedule_futures(introspectors, app, pool)
          introspectors.map do |name, klass|
            future = Concurrent::Future.execute(executor: pool) do
              klass.new(app).call
            ensure
              ActiveRecord::Base.connection_handler.clear_active_connections! if defined?(ActiveRecord::Base)
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
          msg = error.message
          Rails.logger.warn("[rails-ai-bridge] #{name} introspection failed: #{msg}")
          { error: msg }
        end
      end
    end
  end
end
