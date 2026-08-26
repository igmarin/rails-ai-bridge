# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::PinningHttpAdapter do
  let(:adapter) { described_class.new(nil, addresses: addresses, original_host: original_host) }
  let(:addresses) { ['192.0.2.1'] }
  let(:original_host) { 'example.com' }

  describe '#net_http_connection' do
    def build_env(url)
      env = Faraday::Env.new
      env[:url] = URI.parse(url)
      env[:request] = { proxy: nil }
      env
    end

    it 'connects to the first approved address while preserving the original host' do
      http = adapter.net_http_connection(build_env('https://example.com/mcp'))

      expect(http.address).to eq('example.com')
      expect(http.ipaddr).to eq('192.0.2.1')
      expect(http.port).to eq(443)
    end

    it 'uses the URL port when present' do
      http = adapter.net_http_connection(build_env('https://example.com:8443/mcp'))

      expect(http.ipaddr).to eq('192.0.2.1')
      expect(http.port).to eq(8443)
    end

    it 'defaults HTTP to port 80' do
      http = adapter.net_http_connection(build_env('http://example.com/mcp'))

      expect(http.address).to eq('example.com')
      expect(http.ipaddr).to eq('192.0.2.1')
      expect(http.port).to eq(80)
    end

    it 'picks the first address when multiple addresses are approved' do
      adapter = described_class.new(nil, addresses: %w[192.0.2.1 198.51.100.7], original_host: 'example.com')
      http = adapter.net_http_connection(build_env('https://example.com/mcp'))

      expect(http.ipaddr).to eq('192.0.2.1')
      expect(http.address).to eq('example.com')
    end
  end
end
