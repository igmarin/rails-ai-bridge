# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
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
        @allowed_hosts = allowed_hosts.map { |host| normalize_host(host.to_s) }.freeze
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
        scheme = uri.scheme.to_s.downcase
        raw_host = uri.host

        return failure("unsupported scheme #{scheme.inspect}") unless %w[https http].include?(scheme)
        return failure('endpoint is missing a host') if raw_host.to_s.empty?

        host = normalize_host(raw_host)
        host_label = host.inspect
        raw_addresses = @resolver.getaddresses(host)
        return failure("no addresses resolved for #{host_label}") if raw_addresses.empty?

        approved = filter_addresses(raw_addresses, uri, host)
        if approved.any?
          Result.new(success: true, error: nil, uri: canonicalize(uri), addresses: approved)
        else
          failure("endpoint #{host_label} is not permitted by policy")
        end
      rescue URI::InvalidURIError
        failure('endpoint is not a valid URL')
      rescue Resolv::ResolvError, SocketError
        failure('endpoint could not be resolved')
      end

      private

      # @param message [String] safe, credential-free failure message
      # @return [Result]
      def failure(message)
        Result.new(success: false, error: PolicyError.new(message), uri: nil, addresses: nil)
      end

      # @param value [String]
      # @return [String] downcased host with a trailing dot removed
      def normalize_host(value)
        value.to_s.downcase.delete_suffix('.')
      end

      # @param uri [URI]
      # @return [URI]
      def canonicalize(uri)
        uri.dup.tap do |canonical|
          canonical.host = normalize_host(canonical.host)
          # Setting userinfo to an empty string drops both user and password
          # components from the canonical URL, preventing credential leakage.
          canonical.userinfo = ''
          canonical.fragment = nil
        end
      end

      # @param addresses [Array<String>] resolved IP strings
      # @param uri [URI]
      # @param host [String] normalized host name
      # @return [Array<String>] the subset of addresses permitted by the policy
      def filter_addresses(addresses, uri, host)
        addresses.filter do |raw|
          ip = IPAddr.new(raw)

          if ip.loopback?
            @allowed_loopback_ports.include?(uri.port)
          elsif ip.private? || ip.link_local?
            @allow_private_networks
          else
            @allowed_hosts.include?(host)
          end
        rescue IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end
