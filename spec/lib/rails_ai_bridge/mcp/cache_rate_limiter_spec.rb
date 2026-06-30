# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::CacheRateLimiter do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  describe '#allow?' do
    it 'allows requests under the limit' do
      limiter = described_class.new(max_requests: 3, window_seconds: 60, cache: cache)

      3.times do
        expect(limiter.allow?('1.2.3.4')).to be true
      end
    end

    it 'denies when the limit is reached within the window' do
      limiter = described_class.new(max_requests: 2, window_seconds: 60, cache: cache)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be false
    end

    it 'tracks keys independently per IP' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60, cache: cache)

      expect(limiter.allow?('10.0.0.1')).to be true
      expect(limiter.allow?('10.0.0.2')).to be true
    end

    it 'resets the counter after the cache entry expires' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60, cache: cache)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be false

      cache.delete('rab:rl:1.2.3.4')

      expect(limiter.allow?('1.2.3.4')).to be true
    end

    it 'uses the configured key prefix' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60, cache: cache, key_prefix: 'custom')

      limiter.allow?('1.2.3.4')

      expect(cache.exist?('custom:1.2.3.4')).to be true
    end

    it 'uses unknown bucket for blank IP' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60, cache: cache)

      expect(limiter.allow?('')).to be true
      expect(limiter.allow?(nil)).to be false
    end

    it 'falls back to read/write when the cache does not support increment' do
      store = double('cache')
      allow(store).to receive(:respond_to?).with(:increment).and_return(false)
      allow(store).to receive(:write)
      allow(store).to receive(:read).and_return(0, 1)

      limiter = described_class.new(max_requests: 2, window_seconds: 60, cache: store)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(store).to have_received(:write).with('rab:rl:1.2.3.4', 1, expires_in: 60)
    end

    it 'allows all requests when no cache is available' do
      allow(Rails).to receive(:cache).and_return(nil)
      limiter = described_class.new(max_requests: 1, window_seconds: 60, cache: nil)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be true
    end
  end
end
