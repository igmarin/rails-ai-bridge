# frozen_string_literal: true

require 'spec_helper'
require 'resolv'

RSpec.describe RailsAiBridge::Registry::EndpointPolicy do
  subject(:policy) do
    described_class.new(
      resolver: resolver,
      allowed_hosts: allowed_hosts,
      allowed_loopback_ports: [3000, 9292],
      allow_private_networks: allow_private_networks
    )
  end

  let(:resolver) { instance_double(Resolv::DNS) }
  let(:allowed_hosts) { [] }
  let(:allow_private_networks) { false }

  before do
    allow(resolver).to receive(:getaddresses).and_return([])
  end

  describe '#call' do
    it 'rejects an arbitrary public host not on the allowlist' do
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])

      result = policy.call('https://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint is not permitted by policy')
    end

    it 'rejects an unsupported scheme' do
      result = policy.call('ftp://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
    end

    it 'rejects an endpoint containing credentials' do
      result = policy.call('https://user:pass@example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint must not include credentials')
    end

    it 'rejects a malformed URI' do
      result = policy.call('https://example.com:badport/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint is not a valid URL')
    end

    it 'rejects plain HTTP for a public allowlisted host' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])

      result = policy.call('http://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('plain HTTP is only permitted for loopback or private endpoints')
    end

    it 'accepts an uppercase HTTPS scheme' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])

      result = policy.call('HTTPS://example.com/some-tool')

      expect(result).to be_success
      expect(result.uri.scheme).to eq('https')
    end

    it 'rejects an invalid URI without echoing the raw input' do
      result = policy.call('not a url')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint is not a valid URL')
    end

    it 'returns a policy error when DNS resolution fails' do
      allow(resolver).to receive(:getaddresses).and_raise(Resolv::ResolvError.new('timeout'))

      result = policy.call('https://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint could not be resolved')
    end

    it 'returns a policy error when DNS resolution raises a socket error' do
      allow(resolver).to receive(:getaddresses).and_raise(SocketError.new('getaddrinfo: nodename nor servname provided'))

      result = policy.call('https://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint could not be resolved')
    end

    it 'returns a policy error when the resolver raises a timeout error' do
      allow(resolver).to receive(:getaddresses).and_raise(Timeout::Error.new('resolver timed out'))

      result = policy.call('https://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint could not be resolved')
    end

    it 'returns a policy error and logs a sanitized message when the resolver raises unexpectedly' do
      logger = instance_double(Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(resolver).to receive(:getaddresses).and_raise(ArgumentError.new('unexpected resolver failure'))

      expect(logger).to receive(:error) do |message|
        expect(message).to start_with('ArgumentError: endpoint could not be resolved')
        expect(message).not_to include('unexpected resolver failure')
      end

      result = policy.call('https://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint could not be resolved')
    end

    it 'rejects an uppercase HTTP scheme for a public host' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])

      result = policy.call('HTTP://example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('plain HTTP is only permitted for loopback or private endpoints')
    end

    it 'rejects plain HTTP for a link-local address even when private networks are enabled' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['metadata.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: true
      )
      allow(resolver).to receive(:getaddresses).with('metadata.example.com').and_return(['169.254.169.254'])

      result = policy.call('http://metadata.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint is not permitted by policy')
    end

    it 'rejects HTTPS for a link-local address even when private networks are enabled' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['metadata.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: true
      )
      allow(resolver).to receive(:getaddresses).with('metadata.example.com').and_return(['169.254.169.254'])

      result = policy.call('https://metadata.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(result.error.message).to eq('endpoint is not permitted by policy')
    end

    context 'when the host is on the allowlist' do
      let(:allowed_hosts) { ['example.com'] }

      before do
        allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])
      end

      it 'returns the canonical URI and resolved addresses' do
        result = policy.call('https://example.com/some-tool')

        expect(result).to be_success
        expect(result.uri.to_s).to eq('https://example.com/some-tool')
        expect(result.addresses).to eq(['192.0.2.1'])
      end

      it 'strips fragments from the canonical URI' do
        result = policy.call('https://example.com/some-tool#fragment')

        expect(result).to be_success
        expect(result.uri.to_s).to eq('https://example.com/some-tool')
      end

      it 'rejects an endpoint containing credentials even when the host is allowed' do
        result = policy.call('https://user:pass@example.com/some-tool')

        expect(result).not_to be_success
        expect(result.error.message).to eq('endpoint must not include credentials')
      end

      it 'normalizes mixed-case hosts' do
        result = policy.call('https://EXAMPLE.COM/some-tool')

        expect(result).to be_success
        expect(result.uri.host).to eq('example.com')
      end

      context 'when the allowlist entry has a trailing dot' do
        let(:allowed_hosts) { ['example.com.'] }

        it 'treats a trailing dot on the allowlist entry as equivalent to the endpoint host' do
          result = policy.call('https://example.com/some-tool')

          expect(result).to be_success
          expect(result.addresses).to eq(['192.0.2.1'])
        end
      end
    end

    context 'with loopback destinations' do
      before do
        allow(resolver).to receive(:getaddresses).with('localhost').and_return(['127.0.0.1'])
      end

      it 'allows an http loopback endpoint on an allowed port' do
        result = policy.call('http://localhost:3000/some-tool')

        expect(result).to be_success
        expect(result.addresses).to eq(['127.0.0.1'])
      end

      it 'rejects a loopback endpoint on a non-allowed port' do
        result = policy.call('http://localhost:4000/some-tool')

        expect(result).not_to be_success
        expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      end
    end

    context 'with private network destinations' do
      let(:allow_private_networks) { true }

      before do
        allow(resolver).to receive(:getaddresses).with('private.local').and_return(['192.168.1.1'])
      end

      it 'allows a private address when private networks are enabled' do
        result = policy.call('https://private.local/some-tool')

        expect(result).to be_success
        expect(result.addresses).to eq(['192.168.1.1'])
      end

      it 'rejects a private address when private networks are disabled' do
        policy = described_class.new(
          resolver: resolver,
          allowed_hosts: allowed_hosts,
          allowed_loopback_ports: [3000, 9292],
          allow_private_networks: false
        )

        result = policy.call('https://private.local/some-tool')

        expect(result).not_to be_success
        expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      end

      it 'allows an http private address when private networks are enabled' do
        result = policy.call('http://private.local/some-tool')

        expect(result).to be_success
        expect(result.addresses).to eq(['192.168.1.1'])
      end
    end

    it 'rejects a host that resolves to a mix of public and private addresses over http' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['mixed.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: true
      )
      allow(resolver).to receive(:getaddresses).with('mixed.example.com').and_return(%w[192.0.2.1 192.168.1.1])

      result = policy.call('http://mixed.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error.message).to eq('plain HTTP is only permitted for loopback or private endpoints')
    end

    it 'rejects a host that resolves to a mix of public and blocked addresses over https' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['mixed.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('mixed.example.com').and_return(%w[192.0.2.1 169.254.169.254])

      result = policy.call('https://mixed.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error.message).to eq('endpoint resolved to a mix of permitted and blocked addresses')
    end

    it 'rejects a host that mixes an approved private address with a blocked link-local address' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['mixed.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: true
      )
      allow(resolver).to receive(:getaddresses).with('mixed.example.com').and_return(%w[192.168.1.1 169.254.1.1])

      result = policy.call('https://mixed.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error.message).to eq('endpoint resolved to a mix of permitted and blocked addresses')
    end

    it 'rejects a remote https endpoint on a non-default port' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(['192.0.2.1'])

      result = policy.call('https://example.com:8443/some-tool')

      expect(result).not_to be_success
      expect(result.error.message).to eq('remote HTTPS must use the default port 443')
    end

    it 'allows an https loopback endpoint on an allowed non-default port' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: [],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('localhost').and_return(['127.0.0.1'])

      result = policy.call('https://localhost:9292/some-tool')

      expect(result).to be_success
    end

    it 'accepts a host whose addresses are all permitted' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com').and_return(%w[192.0.2.1 198.51.100.7])

      result = policy.call('https://example.com/some-tool')

      expect(result).to be_success
      expect(result.addresses).to eq(%w[192.0.2.1 198.51.100.7])
    end

    it 'normalizes Resolv::DNS answer objects to strings before applying policy' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: false
      )
      allow(resolver).to receive(:getaddresses).with('example.com')
                                               .and_return([Resolv::IPv4.create('192.0.2.1'), Resolv::IPv6.create('2001:db8::1')])

      result = policy.call('https://example.com/some-tool')

      expect(result).to be_success
      expect(result.addresses).to eq(['192.0.2.1', '2001:db8::1'])
    end

    it 'rejects private addresses in production even when allow_private_networks is true' do
      policy = described_class.new(
        resolver: resolver,
        allowed_hosts: ['private.example.com'],
        allowed_loopback_ports: [3000, 9292],
        allow_private_networks: true
      )
      allow(resolver).to receive(:getaddresses).with('private.example.com').and_return(['192.168.1.1'])
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      result = policy.call('https://private.example.com/some-tool')

      expect(result).not_to be_success
      expect(result.error.message).to eq('endpoint is not permitted by policy')
    end
  end
end
