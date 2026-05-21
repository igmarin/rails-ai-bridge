# frozen_string_literal: true

module RailsAiBridge
  class Introspector
    # Executes a single introspector class and measures how long it takes.
    #
    # This is a pure value-object service: it has no state of its own and is
    # not responsible for thread management, error aggregation, or configuration.
    # It does one thing — run an introspector and tell you how long it took.
    #
    # The result hash uses two keys:
    #
    # * +:result+ — the raw return value of the introspector, or
    #   +{ error: message }+ when the introspector raises.
    # * +:duration_ms+ — wall-clock time of the introspector call in
    #   milliseconds, as a +Float+. Available even on error so callers can
    #   diagnose slow-then-failing introspectors.
    #
    # @example
    #   timed = TimedRunner.call(SchemaIntrospector, Rails.application)
    #   timed[:result]      # => { tables: { ... }, ... }
    #   timed[:duration_ms] # => 42.7
    class TimedRunner
      # Instantiates +klass+ with +app+ and calls it, measuring elapsed time.
      #
      # @param klass [Class] an introspector class responding to +.new(app)+ and
      #   +#call+
      # @param app [Rails::Application] the Rails application instance
      # @return [Hash{Symbol => Object}] a hash with +:result+ and +:duration_ms+
      def self.call(klass, app)
        result     = nil
        caught     = nil
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          result = klass.new(app).call
        rescue StandardError => error
          caught = error
        end

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(2)
        payload     = caught ? { error: caught.message } : result
        { result: payload, duration_ms: duration_ms }
      end
    end
  end
end
