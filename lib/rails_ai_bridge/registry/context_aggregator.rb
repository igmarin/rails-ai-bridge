# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Orchestrates fetching context from declared providers through
    # {ContextProviderClient} instances. Iterates providers and their tools
    # sequentially in deterministic order, maps results to declared fields,
    # enforces budgets and count caps, and memoizes within a per-invocation
    # {ProviderRequestScope}.
    #
    # Optional provider failures are recorded as warnings and skipped; required
    # provider failures are visible in the aggregate result. The aggregator
    # never uses a process-wide cache.
    class ContextAggregator
      # Aggregate result of one or more provider fetches.
      #
      # @!attribute [r] results
      #   @return [Hash<String, Hash>] provider-keyed mapped tool results
      # @!attribute [r] failures
      #   @return [Array<ContextProviderError>] typed errors for failed providers
      # @!attribute [r] status
      #   @return [Symbol] one of :success, :partial_failure, :error
      # @!attribute [r] elapsed_ms
      #   @return [Integer] total aggregation elapsed time in milliseconds
      AggregateResult = Data.define(:results, :failures, :status, :elapsed_ms) do
        # @return [Boolean]
        def success? = status == :success

        # @return [Boolean]
        def partial_failure? = status == :partial_failure

        # @return [Boolean]
        def error? = status == :error
      end

      # @param manifest [RegistryManifest] the parsed registry manifest
      # @param config [Config::ContextProviders] provider configuration
      # @param client_factory [Proc] lambda receiving a ContextProviderDefinition
      #   and returning a ContextProviderClient
      # @param scope [ProviderRequestScope] per-invocation memo
      # @return [ContextAggregator]
      def initialize(manifest:, config:, client_factory:, scope:)
        @manifest = manifest
        @config = config
        @client_factory = client_factory
        @scope = scope
      end

      # Fetches all declared providers and returns an aggregate result.
      #
      # @return [AggregateResult]
      def fetch_all
        providers = @manifest.context_providers
        results = {}
        failures = []
        failed_optional = false
        failed_required = false
        start = monotonic_now
        deadline = start + @config.aggregation_budget_seconds

        providers.each_with_index do |(name, provider), index|
          break if index >= @config.max_providers
          break if monotonic_now >= deadline

          outcome = fetch_provider(name, provider, deadline:)
          error = outcome[:error]
          if error
            failures << error
            failed_optional = true if provider.optional?
            failed_required = true unless provider.optional?
            next
          end
          results[name] = outcome[:data]
        end

        AggregateResult.new(
          results: results,
          failures: failures,
          status: aggregate_status(failed_required, failed_optional),
          elapsed_ms: elapsed_ms(start)
        )
      end

      # Fetches a single provider by name and returns its mapped tool results.
      #
      # @param name [String] provider name from the manifest
      # @return [AggregateResult]
      # @raise [ArgumentError] when the provider name is not in the manifest
      def fetch_one(name)
        provider = @manifest.context_providers[name]
        raise ArgumentError, "unknown provider: #{name}" unless provider

        start = monotonic_now
        outcome = fetch_provider(name, provider, deadline: nil)
        elapsed = elapsed_ms(start)
        error = outcome[:error]
        return error_result(error, elapsed) if error

        AggregateResult.new(
          results: outcome[:data] || {},
          failures: [],
          status: :success,
          elapsed_ms: elapsed
        )
      end

      private

      # @param name [String] provider name
      # @param provider [ContextProviderDefinition]
      # @param deadline [Float, nil] monotonic clock deadline; nil skips budget checks
      # @return [Hash] with :data and optional :error keys
      # @api private
      def fetch_provider(name, provider, deadline:)
        validate_no_mapping_collisions!(provider)
        data = {}
        client = @client_factory.call(provider)

        provider.tools.each_with_index do |tool_spec, index|
          break if index >= @config.max_tools_per_provider
          break if deadline && monotonic_now >= deadline

          outcome = fetch_tool(name, client, tool_spec)
          return { data: nil, error: outcome[:error] } if outcome[:error]

          data[tool_spec.field_name] = outcome[:content]
        end

        { data: data, error: nil }
      rescue RailsAiBridge::Registry::ContextProviderError => error
        { data: nil, error: error }
      end

      # @param name [String] provider name
      # @param client [ContextProviderClient]
      # @param tool_spec [ContextToolSpec]
      # @return [Hash] with :content or :error
      def fetch_tool(name, client, tool_spec)
        arguments = tool_spec.arguments || {}
        result = @scope.fetch_or_store(name, tool_spec.name, args_key: arguments) do
          client.call_tool(tool_spec.name, arguments: arguments)
        end
        return { content: result.content } if result.status == :success

        { error: result.error }
      end

      # Rejects two tools mapping to the same field name before any network calls.
      #
      # @param provider [ContextProviderDefinition]
      # @return [void]
      # @raise [RailsAiBridge::ConfigurationError] when two tools map to the same field
      def validate_no_mapping_collisions!(provider)
        fields = provider.tools.map(&:field_name)
        duplicates = fields.tally.select { |_, count| count > 1 }.keys
        return if duplicates.empty?

        raise RailsAiBridge::ConfigurationError,
              "mapping collision: tools #{duplicates.map(&:inspect).join(', ')} map to the same field in provider"
      end

      # @param failed_required [Boolean]
      # @param failed_optional [Boolean]
      # @return [Symbol]
      def aggregate_status(failed_required, failed_optional)
        return :error if failed_required
        return :partial_failure if failed_optional

        :success
      end

      # @param error [ContextProviderError]
      # @param elapsed [Integer]
      # @return [AggregateResult]
      def error_result(error, elapsed)
        AggregateResult.new(results: {}, failures: [error], status: :error, elapsed_ms: elapsed)
      end

      # @return [Float]
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # @param start [Float] monotonic clock start
      # @return [Integer] elapsed milliseconds
      def elapsed_ms(start)
        ((monotonic_now - start) * 1000).to_i
      end
    end
  end
end
