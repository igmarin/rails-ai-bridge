# frozen_string_literal: true

require 'ipaddr'
require 'uri'

module RailsAiBridge
  module Registry
    # Validates an external provider endpoint against the configured host
    # allowlist, scheme rules, and network restrictions. It returns a typed
    # result rather than raising, keeping policy decisions explicit and
    # testable without network I/O.
    class EndpointPolicy
      # Result of an endpoint policy check.
      #
      # @!attribute success
      #   @return [Boolean] whether the endpoint was approved
      # @!attribute error
      #   @return [ContextProviderError, nil] the policy violation when not approved
      # @!attribute uri
      #   @return [URI, nil] canonical URI with userinfo and fragment stripped
      # @!attribute addresses
      #   @return [Array<String>, nil] approved IP addresses for the transport
      Result = Struct.new(:success, :error, :uri, :addresses, keyword_init: true) do
        # @return [Boolean]
        def success?
          success
        end
      end

      # @param resolver [#getaddresses] injected DNS resolver; returns an array of IP strings
      # @param allowed_hosts [Array<String>] exact allowed hostnames or public IP strings
      # @param allowed_loopback_ports [Array<Integer>] allowed loopback ports
      # @param allow_private_networks [Boolean] whether private/link-local network destinations are allowed
      # @return [EndpointPolicy]
      def initialize(resolver:, allowed_hosts:, allowed_loopback_ports:, allow_private_networks:)
        @resolver = resolver
        @allowed_hosts = allowed_hosts.map(&:to_s).freeze
        @allowed_loopback_ports = allowed_loopback_ports.map(&:to_i).freeze
        @allow_private_networks = allow_private_networks
      end

      # Checks the endpoint against scheme, host, and network policy.
      #
      # @param endpoint [String] the raw endpoint URL
      # @return [Result] a successful result with the canonical URI and approved
      #   addresses, or a failure result with a {PolicyError}
      def call(endpoint)
        uri = URI.parse(endpoint)

        return failure("unsupported scheme #{uri.scheme.inspect}") unless %w[https http].include?(uri.scheme)

        return failure('endpoint is missing a host') if uri.host.blank?

        raw_addresses = @resolver.getaddresses(uri.host)
        return failure("no addresses resolved for #{uri.host.inspect}") if raw_addresses.empty?

        approved = filter_addresses(raw_addresses, uri)
        if approved.any?
          Result.new(success: true, error: nil, uri: canonicalize(uri), addresses: approved)
        else
          failure("endpoint #{uri.host.inspect} is not permitted by policy")
        end
      rescue URI::InvalidURIError => error
        failure("invalid endpoint: #{error.message}")
      end

      private

      # @param message [String] safe, credential-free failure message
      # @return [Result]
      def failure(message)
        Result.new(success: false, error: PolicyError.new(message), uri: nil, addresses: nil)
      end

      # @param uri [URI]
      # @return [URI]
      def canonicalize(uri)
        uri.dup.tap do |u|
          u.user = nil
          u.password = nil
          u.fragment = nil
        end
      end

      # @param addresses [Array<String>] resolved IP strings
      # @param uri [URI]
      # @return [Array<String>] the subset of addresses permitted by the policy
      def filter_addresses(addresses, uri)
        addresses.filter do |raw|
          ip = IPAddr.new(raw)

          if ip.loopback?
            @allowed_loopback_ports.include?(uri.port)
          elsif ip.private? || ip.link_local?
            @allow_private_networks
          else
            @allowed_hosts.include?(uri.host.to_s)
          end
        rescue IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end
