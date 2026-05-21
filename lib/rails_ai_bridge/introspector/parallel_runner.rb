# frozen_string_literal: true

module RailsAiBridge
  class Introspector
    # Runs multiple introspectors concurrently using a fixed thread pool.
    #
    # Requires +concurrent-ruby+ (already a transitive dependency of Rails).
    # Falls back gracefully when the gem is unavailable — callers should
    # check {.available?} before using this runner.
    #
    # Pool size and per-future timeout are driven by
    # {RailsAiBridge::Configuration} (+parallel_pool_size+ and
    # +parallel_timeout_seconds+), so hosts can tune concurrency without
    # touching this class.
    #
    # Each introspector is executed in its own future. Errors — including
    # per-future timeouts — are captured per-introspector and returned as
    # +{ error: message }+ hashes, matching the convention used throughout
    # {Introspector#call}.
    #
    # @example Basic usage
    #   results = ParallelRunner.call(introspectors, Rails.application)
    #   results[:schema] #=> { tables: { ... } }
    #   results[:slow]   #=> { error: "timed out after 10s" }
    class ParallelRunner
      class << self
        # Runs +introspectors+ concurrently and returns a Hash of results.
        #
        # The number of threads is +min(introspectors.size, parallel_pool_size)+.
        # Each future is given +parallel_timeout_seconds+ to complete; if it
        # exceeds the timeout the result is +{ error: "timed out after Ns" }+.
        #
        # The thread pool is always shut down in an +ensure+ block, even if
        # an unexpected exception escapes.
        #
        # @param introspectors [Hash{Symbol => Class}] name → introspector class
        # @param app [Rails::Application] the host application
        # @return [Hash{Symbol => Object}] results keyed by introspector name
        def call(introspectors, app)
          return {} if introspectors.empty?

          cfg      = RailsAiBridge.configuration
          size     = [introspectors.size, cfg.parallel_pool_size].min
          timeout  = cfg.parallel_timeout_seconds
          pool     = Concurrent::FixedThreadPool.new(size)
          futures  = schedule_futures(introspectors, app, pool)
          collect_results(futures, timeout)
        ensure
          pool&.shutdown
          pool&.wait_for_termination(timeout || 10)
        end

        # Returns +true+ when parallel execution is safe to use.
        #
        # Parallel execution is considered unsafe when:
        # * +concurrent-ruby+ is not loaded (+Concurrent::Future+ is undefined)
        # * ActiveRecord's connection pool has only one slot (common in
        #   transactional tests or SQLite single-connection setups)
        #
        # @return [Boolean]
        def available?
          return false unless defined?(Concurrent::Future) == 'constant'

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

        # @param introspectors [Hash{Symbol => Class}]
        # @param app [Rails::Application]
        # @param pool [Concurrent::FixedThreadPool]
        # @return [Array<Array(Symbol, Concurrent::Future)>]
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

        # @param futures [Array<Array(Symbol, Concurrent::Future)>]
        # @param timeout [Numeric] seconds to wait per future
        # @return [Hash{Symbol => Object}]
        def collect_results(futures, timeout)
          futures.each_with_object({}) do |(name, future), results|
            results[name] = resolve_future(name, future, timeout)
          end
        end

        # Resolves a single future, enforcing +timeout+.
        #
        # +future.value(timeout)+ returns +nil+ when the timeout expires
        # (rather than the actual nil return value of a future), so we check
        # for +future.pending?+ / +future.incomplete?+ afterward to distinguish
        # a genuine +nil+ result from a timeout.
        #
        # @param name [Symbol]
        # @param future [Concurrent::Future]
        # @param timeout [Numeric]
        # @return [Object, Hash{error: String}]
        def resolve_future(name, future, timeout)
          value = future.value(timeout)

          if future.complete?
            return { error: future.reason&.message || future.reason.inspect } if future.rejected?

            value
          else
            future.cancel
            msg = "timed out after #{timeout}s"
            Rails.logger.warn("[rails-ai-bridge] #{name} introspection #{msg}")
            { error: msg }
          end
        rescue StandardError => error
          msg = error.message
          Rails.logger.warn("[rails-ai-bridge] #{name} introspection failed: #{msg}")
          { error: msg }
        end
      end
    end
  end
end
