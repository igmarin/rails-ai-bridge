# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Fingerprinter::CachedSnapshot do
  let(:app) { Rails.application }
  let(:fingerprint_a) { 'aaa111' }
  let(:fingerprint_b) { 'bbb222' }

  before { described_class.reset! }
  after { described_class.reset! }

  describe '.fetch' do
    it 'computes a fresh snapshot on first call' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a)

      result = described_class.fetch(app)

      expect(result).to eq(fingerprint_a)
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).once
    end

    it 'returns cached snapshot within snapshot_ttl without re-walking filesystem' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a)

      first = described_class.fetch(app)
      second = described_class.fetch(app)

      expect(first).to eq(fingerprint_a)
      expect(second).to eq(fingerprint_a)
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).once
    end

    it 're-computes snapshot after snapshot_ttl expires' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a, fingerprint_b)

      described_class.fetch(app)

      # Simulate TTL expiry by manipulating the fetched_at timestamp
      cache = described_class.instance_variable_get(:@cache)
      entry = cache.values.first
      entry[:fetched_at] -= described_class.snapshot_ttl + 1

      result = described_class.fetch(app)

      expect(result).to eq(fingerprint_b)
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).twice
    end

    it 'is thread-safe' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a)

      threads = Array.new(5) { Thread.new { described_class.fetch(app) } }
      results = threads.map(&:value)

      expect(results).to all(eq(fingerprint_a))
    end
  end

  describe '.snapshot_ttl' do
    it 'defaults to 5 seconds' do
      expect(described_class.snapshot_ttl).to eq(5)
    end
  end

  describe '.snapshot_ttl=' do
    it 'allows configuring the snapshot TTL' do
      original = described_class.snapshot_ttl
      described_class.snapshot_ttl = 10
      expect(described_class.snapshot_ttl).to eq(10)
    ensure
      described_class.snapshot_ttl = original
    end
  end

  describe '.reset!' do
    it 'clears all cached snapshots' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a, fingerprint_b)

      described_class.fetch(app)
      described_class.reset!
      result = described_class.fetch(app)

      expect(result).to eq(fingerprint_b)
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).twice
    end
  end

  describe '.invalidate!' do
    it 'forces re-computation on next fetch for a specific app' do
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint_a, fingerprint_b)

      described_class.fetch(app)
      described_class.invalidate!(app)
      result = described_class.fetch(app)

      expect(result).to eq(fingerprint_b)
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).twice
    end
  end
end
