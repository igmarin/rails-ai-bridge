# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'socket'
require 'timeout'
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
      # @param timeout_seconds [Numeric, nil] per-call DNS resolution timeout in seconds; nil disables the timeout
      # @param max_resolved_addresses [Integer, nil] maximum number of addresses to accept from DNS; nil disables the cap
      # @return [EndpointPolicy]
      def initialize(resolver:, allowed_hosts:, allowed_loopback_ports:, allow_private_networks:, timeout_seconds: nil, max_resolved_addresses: nil)
        @resolver = resolver
        @allowed_hosts = allowed_hosts.map { |host| normalize_host(host.to_s) }.freeze
        @allowed_loopback_ports = allowed_loopback_ports.map(&:to_i).freeze
        @allow_private_networks = allow_private_networks
        @timeout_seconds = timeout_seconds
        @max_resolved_addresses = max_resolved_addresses
        return unless @max_resolved_addresses && (!@max_resolved_addresses.is_a?(Integer) || @max_resolved_addresses <= 0)

        raise RailsAiBridge::ConfigurationError,
              "max_resolved_addresses must be a positive integer, got #{max_resolved_addresses.inspect}"
      end

      # Checks the endpoint against scheme, host, and network policy.
      #
      # @param endpoint [String] the raw endpoint URL
      # @return [Result] a successful result with the canonical URI and approved
      #   addresses, or a failure result with a {PolicyError}
      def call(endpoint)
        uri = URI.parse(endpoint)
        return failure('endpoint must not include credentials') if uri.userinfo

        scheme = uri.scheme.to_s.downcase
        raw_host = uri.host

        return failure("unsupported scheme #{scheme.inspect}") unless %w[https http].include?(scheme)
        return failure('endpoint is missing a host') if raw_host.to_s.empty?

        host = normalize_host(raw_host)
        host_label = host.inspect
        raw_addresses = resolve_with_timeout(host).map(&:to_s)
        address_count = raw_addresses.length
        return failure("no addresses resolved for #{host_label}") if address_count.zero?

        return failure('endpoint resolved to too many addresses') if @max_resolved_addresses && address_count > @max_resolved_addresses

        approved = filter_addresses(raw_addresses, uri, host)
        # Fail closed when any resolved address is rejected. Approving only the
        # permitted subset would still let an unpinned transport re-resolve DNS
        # and connect to a blocked address, so every answer must pass policy.
        if approved.empty?
          failure('endpoint is not permitted by policy')
        elsif approved.length < address_count
          failure('endpoint resolved to a mix of permitted and blocked addresses')
        else
          # AC-2b: remote HTTPS is restricted to the default port so an allowlisted
          # host cannot be used to reach arbitrary ports on that host.
          non_default_https = scheme == 'https' && uri.port != URI::HTTPS::DEFAULT_PORT
          remote_endpoint = !approved.all? { |raw| loopback_address?(raw) }
          return failure('remote HTTPS must use the default port 443') if non_default_https && remote_endpoint

          return failure('plain HTTP is only permitted for loopback or private endpoints') if scheme == 'http' && !plaintext_permitted?(approved)

          Result.new(success: true, error: nil, uri: canonicalize(uri), addresses: approved)
        end
      rescue URI::Error
        failure('endpoint is not a valid URL')
      rescue Resolv::ResolvError, SocketError, Timeout::Error, IPAddr::Error
        resolve_failure
      rescue RailsAiBridge::Registry::TimeoutError
        # Re-raise client-level timeout exceptions so callers can classify the
        # whole policy evaluation as a timeout, not a policy rejection.
        raise
      rescue StandardError => error
        log_error(error)
        resolve_failure
      end

      private

      # Resolves the host with an optional timeout to prevent DNS stalls.
      #
      # When the resolver is a Resolv::DNS, the per-query timeout list is
      # configured so the resolver itself enforces the deadline.  For other
      # resolvers, the call is wrapped in Timeout.timeout as a fallback.
      #
      # @param host [String] normalized host name
      # @return [Array<Object>] addresses returned by the resolver
      def resolve_with_timeout(host)
        configure_resolver_timeout

        get_addresses = proc { @resolver.getaddresses(host) }
        return get_addresses.call unless @timeout_seconds

        Timeout.timeout(@timeout_seconds, &get_addresses)
      end

      # @return [void]
      def configure_resolver_timeout
        return unless @timeout_seconds

        @resolver.timeouts = [@timeout_seconds]
      rescue NoMethodError
        # Resolver does not support per-query timeouts; fall back to Timeout.timeout.
        nil
      end

      # @return [Result]
      def resolve_failure
        failure('endpoint could not be resolved')
      end

      # @param error [StandardError]
      # @return [void]
      def log_error(error)
        logger = defined?(Rails) ? Rails.logger : nil
        return unless logger

        lines = ["#{error.class}: endpoint could not be resolved"]
        backtrace = error.backtrace
        lines.concat(backtrace.first(5)) if backtrace
        logger.error(lines.join("\n"))
      end

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
          elsif ip.link_local?
            false
          elsif ip.private?
            @allow_private_networks && !production?
          else
            @allowed_hosts.include?(host)
          end
        rescue IPAddr::InvalidAddressError
          false
        end
      end

      # @return [Boolean] whether the runtime environment is a Rails production environment
      def production?
        defined?(Rails) && Rails.respond_to?(:env) && Rails.env&.production?
      end

      # @param raw [String] IP address string
      # @return [Boolean] whether the address is a loopback address
      def loopback_address?(raw)
        IPAddr.new(raw).loopback?
      rescue IPAddr::InvalidAddressError
        false
      end

      # @param addresses [Array<String>] approved IP strings
      # @return [Boolean] whether all addresses are safe for plain HTTP
      def plaintext_permitted?(addresses)
        addresses.all? do |raw|
          ip = IPAddr.new(raw)
          local_address?(ip)
        rescue IPAddr::InvalidAddressError
          false
        end
      end

      # @param ip [IPAddr]
      # @return [Boolean] whether the address is loopback or an allowed RFC1918/ULA private address
      def local_address?(ip)
        return true if ip.loopback?

        ip.private? && @allow_private_networks
      end
    end
  end
end
