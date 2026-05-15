# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::RubydexAdapter do
  after do
    described_class.reset!
    described_class.reset_availability!
  end

  describe '.available?' do
    it 'returns false when rubydex gem is not installed' do
      described_class.reset_availability!
      expect(described_class.available?).to be(false)
    end

    it 'caches the availability check' do
      described_class.reset_availability!
      result1 = described_class.available?
      result2 = described_class.available?
      expect(result1).to eq(result2)
    end
  end

  describe '.instance' do
    it 'returns an adapter instance' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.instance(Rails.root.to_s)
      expect(adapter).to be_a(described_class)
    end

    it 'caches the instance for the same root' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter1 = described_class.instance(Rails.root.to_s)
      adapter2 = described_class.instance(Rails.root.to_s)
      expect(adapter1).to equal(adapter2)
    end

    it 'rebuilds instance when root changes' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter1 = described_class.instance('/tmp/root1')
      adapter2 = described_class.instance('/tmp/root2')
      expect(adapter1).not_to equal(adapter2)
    end
  end

  describe '#indexed?' do
    it 'returns false when rubydex is not available' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      adapter.index!
      expect(adapter.indexed?).to be(false)
    end
  end

  describe '#search' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.search('User')).to eq([])
    end
  end

  describe '#get_declaration' do
    it 'returns nil when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.get_declaration('User')).to be_nil
    end
  end

  describe '#all_declarations' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.all_declarations).to eq([])
    end
  end

  describe '#file_declarations' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.file_declarations('app/models/user.rb')).to eq([])
    end
  end

  describe '#descendants' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.descendants('User')).to eq([])
    end
  end

  describe '#ancestors' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.ancestors('User')).to eq([])
    end
  end

  describe '#constant_references' do
    it 'returns empty array when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.constant_references).to eq([])
    end
  end

  describe '#codebase_stats' do
    it 'returns empty hash when not indexed' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter = described_class.new(Rails.root.to_s)
      expect(adapter.codebase_stats).to eq({})
    end
  end
end
