# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::StaticAnalysis do
  let(:config) { described_class.new }

  it 'has confidence tags enabled by default' do
    expect(config.confidence_tags_enabled).to be(true)
  end

  it 'has the Prism pass disabled by default' do
    expect(config.prism_enabled).to be(false)
  end

  it 'caps Prism scans at 500 files by default' do
    expect(config.prism_max_files).to eq(500)
  end

  it 'is configurable' do
    config.confidence_tags_enabled = false
    config.prism_enabled = true
    config.prism_max_files = 50

    expect(config.confidence_tags_enabled).to be(false)
    expect(config.prism_enabled).to be(true)
    expect(config.prism_max_files).to eq(50)
  end
end

RSpec.describe RailsAiBridge::Configuration do
  let(:config) { described_class.new }

  it 'exposes the static_analysis sub-config' do
    expect(config.static_analysis).to be_a(RailsAiBridge::Config::StaticAnalysis)
  end

  it 'delegates confidence_tags_enabled to the static_analysis sub-config' do
    config.confidence_tags_enabled = false
    expect(config.static_analysis.confidence_tags_enabled).to be(false)
  end

  it 'delegates prism_enabled to the static_analysis sub-config' do
    config.prism_enabled = true
    expect(config.static_analysis.prism_enabled).to be(true)
  end

  it 'delegates prism_max_files to the static_analysis sub-config' do
    config.prism_max_files = 10
    expect(config.static_analysis.prism_max_files).to eq(10)
  end
end
