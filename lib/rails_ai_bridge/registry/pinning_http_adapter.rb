# frozen_string_literal: true

require 'faraday'

begin
  require 'net/https'
rescue LoadError
  require 'net/http'
end

module RailsAiBridge
  module Registry
    # Faraday adapter that pins a provider connection to one of the IP addresses
    # already approved by {EndpointPolicy}, while preserving the original Host
    # header and TLS SNI.
    #
    # The default Faraday :net_http adapter resolves the URL hostname at connect
    # time, which allows a DNS rebinding attack to bypass the SSRF allowlist.
    # This adapter closes that gap by connecting directly to a policy-validated
    # address and setting Net::HTTP#hostname to the original host so certificate
    # validation and SNI continue to work.
    class PinningHttpAdapter < Faraday::Adapter::NetHttp
      # @param app [#call] the next middleware/adapter in the Faraday stack
      # @param addresses [Array<String>] policy-approved IP addresses
      # @param original_host [String] the original hostname from the canonical URI
      # @param opts [Hash] standard Faraday adapter options
      def initialize(app = nil, addresses:, original_host:, **opts, &)
        @addresses = Array(addresses)
        @original_host = original_host
        super(app, opts, &)
      end

      # Builds a Net::HTTP connection that connects to the pinned address while
      # presenting the original hostname for SNI and the Host header.
      #
      # @param env [Faraday::Env]
      # @return [Net::HTTP]
      def net_http_connection(env)
        super.tap do |http|
          http.ipaddr = @addresses.first
        end
      end
    end
  end
end
