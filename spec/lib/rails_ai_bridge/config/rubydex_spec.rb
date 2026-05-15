# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Rubydex do
  let(:config) { described_class.new }

  it 'has rubydex disabled by default' do
    expect(config.rubydex_enabled).to be(false)
  end

  it 'has default index path' do
    expect(config.rubydex_index_path).to eq('tmp/rubydex_index')
  end

  it 'has semantic introspector disabled by default' do
    expect(config.semantic_introspector_enabled).to be(false)
  end

  it 'has standard semantic context depth by default' do
    expect(config.semantic_context_depth).to eq(:standard)
  end

  it 'is configurable' do
    config.rubydex_enabled = true
    config.rubydex_index_path = 'custom/path'
    config.semantic_introspector_enabled = true
    config.semantic_context_depth = :full

    expect(config.rubydex_enabled).to be(true)
    expect(config.rubydex_index_path).to eq('custom/path')
    expect(config.semantic_introspector_enabled).to be(true)
    expect(config.semantic_context_depth).to eq(:full)
  end
end

RSpec.describe RailsAiBridge::Configuration do
  let(:config) { described_class.new }

  it 'exposes the rubydex sub-config' do
    expect(config.rubydex).to be_a(RailsAiBridge::Config::Rubydex)
  end

  it 'delegates rubydex_enabled to rubydex sub-config' do
    config.rubydex_enabled = true
    expect(config.rubydex.rubydex_enabled).to be(true)
  end

  it 'delegates rubydex_index_path to rubydex sub-config' do
    config.rubydex_index_path = 'custom/index'
    expect(config.rubydex.rubydex_index_path).to eq('custom/index')
  end

  it 'delegates semantic_introspector_enabled to rubydex sub-config' do
    config.semantic_introspector_enabled = true
    expect(config.rubydex.semantic_introspector_enabled).to be(true)
  end

  it 'delegates semantic_context_depth to rubydex sub-config' do
    config.semantic_context_depth = :full
    expect(config.rubydex.semantic_context_depth).to eq(:full)
  end

  describe '#rubydex_available?' do
    after do
      RailsAiBridge::RubydexAdapter.reset_availability!
    end

    it 'returns false when rubydex is disabled' do
      config.rubydex_enabled = false
      expect(config.rubydex_available?).to be(false)
    end

    it 'returns false when rubydex is enabled but gem not installed' do
      config.rubydex_enabled = true
      allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(false)
      expect(config.rubydex_available?).to be(false)
    end

    it 'returns true when rubydex is enabled and gem is installed' do
      config.rubydex_enabled = true
      allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(true)
      expect(config.rubydex_available?).to be(true)
    end
  end
end
