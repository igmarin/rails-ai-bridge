# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::HttpRateLimiter do
  describe '#allow?' do
    it 'allows requests under the limit' do
      limiter = described_class.new(max_requests: 3, window_seconds: 60)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be true
    end

    it 'denies when the limit is reached within the window' do
      limiter = described_class.new(max_requests: 2, window_seconds: 60)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be false
    end

    it 'tracks keys independently per IP' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60)

      expect(limiter.allow?('10.0.0.1')).to be true
      expect(limiter.allow?('10.0.0.2')).to be true
    end

    it 'resets the window after time advances' do
      tick = [1_000.0]
      clock = -> { tick.first }
      limiter = described_class.new(max_requests: 1, window_seconds: 10, clock: clock)

      expect(limiter.allow?('1.2.3.4')).to be true
      expect(limiter.allow?('1.2.3.4')).to be false

      tick[0] = 1_020.0

      expect(limiter.allow?('1.2.3.4')).to be true
    end

    it 'reclaims expired clients that never request again' do
      tick = [100.0]
      limiter = described_class.new(max_requests: 2, window_seconds: 10, clock: -> { tick.first })
      1_000.times { |index| limiter.allow?("client-#{index}") }

      tick[0] = 111.0
      limiter.allow?('fresh-client')

      expect(limiter.instance_variable_get(:@hits).size).to eq(1)
    end

    it 'does not discard live counters when the client capacity is reached' do
      tick = [100.0]
      limiter = described_class.new(max_requests: 1, window_seconds: 10, clock: -> { tick.first })
      10_000.times { |index| limiter.allow?("client-#{index}") }

      expect(limiter.allow?('new-client')).to be(false)
      expect(limiter.allow?('client-0')).to be(false)
      expect(limiter.instance_variable_get(:@hits).size).to eq(10_000)
    end

    it 'admits new clients when a full set of counters expires' do
      tick = [100.0]
      limiter = described_class.new(max_requests: 1, window_seconds: 10, clock: -> { tick.first })
      10_000.times { |index| limiter.allow?("client-#{index}") }
      tick[0] = 111.0

      expect(limiter.allow?('new-client')).to be(true)
      expect(limiter.instance_variable_get(:@hits).size).to eq(1)
    end

    it 'reclaims idle clients while retaining a recently active counter' do
      tick = [100.0]
      limiter = described_class.new(max_requests: 2, window_seconds: 10, clock: -> { tick.first })
      limiter.allow?('active')
      tick[0] = 105.0
      limiter.allow?('idle')
      tick[0] = 108.0
      limiter.allow?('active')
      tick[0] = 111.0
      limiter.allow?('other')
      tick[0] = 116.0
      limiter.allow?('other')

      expect(limiter.instance_variable_get(:@hits).keys).to contain_exactly('active', 'other')
    end

    it 'keeps hits exactly on the window boundary until time advances past them' do
      tick = [100.0]
      limiter = described_class.new(max_requests: 1, window_seconds: 10, clock: -> { tick.first })
      limiter.allow?('client')
      tick[0] = 110.0
      expect(limiter.allow?('client')).to be(false)
      tick[0] = 110.001
      expect(limiter.allow?('client')).to be(true)
    end

    it 'uses unknown bucket for blank IP' do
      limiter = described_class.new(max_requests: 1, window_seconds: 60)

      expect(limiter.allow?('')).to be true
      expect(limiter.allow?(nil)).to be false
    end

    it 'drops the per-client hash entry when all hits fall outside the window' do
      tick = [100.0]
      clock = -> { tick.first }
      limiter = described_class.new(max_requests: 5, window_seconds: 10, clock: clock)

      limiter.allow?('192.0.2.1')
      expect(limiter.instance_variable_get(:@hits)).to have_key('192.0.2.1')

      tick[0] = 200.0
      limiter.allow?('192.0.2.1')

      hits = limiter.instance_variable_get(:@hits)
      expect(hits['192.0.2.1']).to eq([200.0])
    end
  end
end
