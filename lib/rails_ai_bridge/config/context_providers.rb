# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds outbound context-provider settings: enable switch, host allowlist,
    # loopback ports, private-network override, timeouts, response limits,
    # provider and tool count caps, aggregation budget, and downstream auth resolver.
    class ContextProviders
      # @return [Boolean] whether outbound provider traffic is allowed
      attr_accessor :enabled

      # @return [Array<String>] exact allowed hostnames; no wildcards or suffixes
      attr_accessor :allowed_hosts

      # @return [Array<Integer>] allowed loopback ports for HTTP development endpoints
      attr_accessor :allowed_loopback_ports

      # @return [Boolean] whether private/link-local network destinations are allowed
      attr_accessor :allow_private_networks

      # @return [Proc, nil] lambda returning auth headers for a configured provider identity
      attr_accessor :auth_resolver

      # @return [Numeric] per-tool connect/read timeout in seconds
      attr_reader :timeout_seconds

      # @return [Numeric] total budget across all providers in one tool call, in seconds
      attr_reader :aggregation_budget_seconds

      # @return [Integer] maximum provider response body size in bytes before normalization
      attr_reader :max_response_bytes

      # @return [Integer] maximum providers to call in one tool invocation
      attr_reader :max_providers

      # @return [Integer] maximum tools to call per provider
      attr_reader :max_tools_per_provider

      # @return [ContextProviders]
      def initialize
        @enabled = false
        @allowed_hosts = []
        @allowed_loopback_ports = [3000, 9292]
        @timeout_seconds = 10
        @aggregation_budget_seconds = 30
        @max_response_bytes = 1_048_576
        @max_providers = 8
        @max_tools_per_provider = 16
        @allow_private_networks = false
        @auth_resolver = nil
      end

      # Sets the per-tool connect/read timeout.
      #
      # @param value [Numeric, #to_f] timeout in seconds; must be finite and >= 0.1
      # @return [Numeric] the validated timeout
      # @raise [RailsAiBridge::ConfigurationError] when the value is not a finite positive number
      def timeout_seconds=(value)
        @timeout_seconds = coerce_timeout(value, 'timeout_seconds')
      end

      # Sets the total aggregation budget across all providers.
      #
      # @param value [Numeric, #to_f] budget in seconds; must be finite and >= 0.1
      # @return [Numeric] the validated budget
      # @raise [RailsAiBridge::ConfigurationError] when the value is not a finite positive number
      def aggregation_budget_seconds=(value)
        @aggregation_budget_seconds = coerce_timeout(value, 'aggregation_budget_seconds')
      end

      # Sets the maximum provider response body size before normalization.
      #
      # @param value [Integer, #to_i] size in bytes; must be an integer >= 1
      # @return [Integer] the validated size
      # @raise [RailsAiBridge::ConfigurationError] when the value is not an integer >= 1
      def max_response_bytes=(value)
        @max_response_bytes = coerce_count(value, 'max_response_bytes')
      end

      # Sets the maximum number of providers to call in one invocation.
      #
      # @param value [Integer, #to_i] count; must be an integer >= 1
      # @return [Integer] the validated count
      # @raise [RailsAiBridge::ConfigurationError] when the value is not an integer >= 1
      def max_providers=(value)
        @max_providers = coerce_count(value, 'max_providers')
      end

      # Sets the maximum number of tools to call per provider.
      #
      # @param value [Integer, #to_i] count; must be an integer >= 1
      # @return [Integer] the validated count
      # @raise [RailsAiBridge::ConfigurationError] when the value is not an integer >= 1
      def max_tools_per_provider=(value)
        @max_tools_per_provider = coerce_count(value, 'max_tools_per_provider')
      end

      private

      def coerce_count(value, field)
        int = Integer(value)
        raise ConfigurationError, "#{field} must be an integer >= 1, got #{int}" unless int >= 1

        int
      rescue ArgumentError, TypeError
        raise ConfigurationError, "#{field} must be an integer >= 1, got #{value.inspect}"
      end

      def coerce_timeout(value, field)
        number = Float(value)
        raise ConfigurationError, "#{field} must be a finite positive number, got #{number}" unless number.finite?
        raise ConfigurationError, "#{field} must be >= 0.1, got #{number}" unless number >= 0.1

        number
      rescue ArgumentError, TypeError
        raise ConfigurationError, "#{field} must be a finite positive number, got #{value.inspect}"
      end
    end
  end
end
