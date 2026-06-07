# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ResolverCache do
  let(:config) do
    instance_double(
      RailsAiBridge::Config::Registry,
      resolver_ttl: 1800
    )
  end
  let(:resolver_a) { instance_double(RailsAiBridge::Registry::Resolver) }
  let(:resolver_b) { instance_double(RailsAiBridge::Registry::Resolver) }
  let(:cache) { described_class.new }

  describe '#fetch' do
    context 'when cache is empty' do
      it 'calls the build block and returns the result' do
        result = cache.fetch(config) { resolver_a }

        expect(result).to eq(resolver_a)
      end
    end

    context 'when cache is warm and TTL has not expired' do
      before { cache.fetch(config) { resolver_a } }

      it 'returns the cached resolver without calling the block again' do
        calls = 0
        result = cache.fetch(config) do
          calls += 1
          resolver_b
        end

        expect(result).to eq(resolver_a)
        expect(calls).to eq(0)
      end
    end

    context 'when TTL has expired' do
      let(:config) { instance_double(RailsAiBridge::Config::Registry, resolver_ttl: 0) }

      before { cache.fetch(config) { resolver_a } }

      it 'rebuilds and returns a fresh resolver' do
        sleep(0.01) # ensure monotonic clock advances past 0-second TTL
        result = cache.fetch(config) { resolver_b }

        expect(result).to eq(resolver_b)
      end
    end

    context 'when block returns nil (manifest missing)' do
      it 'returns nil and does not cache the nil result' do
        result = cache.fetch(config) { nil } # rubocop:disable Style/RedundantFetchBlock

        expect(result).to be_nil

        # Second call should invoke block again, not cache nil
        calls = 0
        cache.fetch(config) do
          calls += 1
          nil
        end
        expect(calls).to eq(1)
      end
    end
  end

  describe '#invalidate!' do
    before { cache.fetch(config) { resolver_a } }

    it 'forces the next fetch to rebuild' do
      cache.invalidate!

      result = cache.fetch(config) { resolver_b }
      expect(result).to eq(resolver_b)
    end
  end

  describe 'thread safety' do
    it 'allows concurrent fetches without raising' do
      builds = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do
        Thread.new do
          cache.fetch(config) do
            builds.increment
            resolver_a
          end
        end
      end
      threads.each(&:join)

      expect(builds.value).to be >= 1
    end
  end
end
