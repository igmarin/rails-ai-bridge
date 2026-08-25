# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ProviderRequestScope do
  let(:scope) { described_class.new }

  describe '#fetch_or_store' do
    it 'stores and returns the block result for a new key' do
      result = scope.fetch_or_store('billing', 'get_status') { { 'status' => 'ok' } }

      expect(result).to eq({ 'status' => 'ok' })
    end

    it 'returns the cached result on a repeat lookup without calling the block' do
      scope.fetch_or_store('billing', 'get_status') { { 'status' => 'first' } }
      calls = 0
      result = scope.fetch_or_store('billing', 'get_status') do
        calls += 1
        { 'status' => 'second' }
      end

      expect(result).to eq({ 'status' => 'first' })
      expect(calls).to eq(0)
    end

    it 'treats different provider/tool pairs as distinct keys' do
      scope.fetch_or_store('billing', 'get_status') { 'a' }
      scope.fetch_or_store('billing', 'get_invoice') { 'b' }
      scope.fetch_or_store('inventory', 'get_status') { 'c' }

      expect(scope.fetch_or_store('billing', 'get_status') { 'x' }).to eq('a')
      expect(scope.fetch_or_store('billing', 'get_invoice') { 'x' }).to eq('b')
      expect(scope.fetch_or_store('inventory', 'get_status') { 'x' }).to eq('c')
    end
  end

  describe '#clear' do
    it 'removes all cached entries' do
      scope.fetch_or_store('billing', 'get_status') { 'cached' }
      scope.clear

      result = scope.fetch_or_store('billing', 'get_status') { 'fresh' }

      expect(result).to eq('fresh')
    end
  end
end
