# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::PackDefinition do
  describe '#always_loaded?' do
    it 'returns true when always_loaded is true' do
      pack = described_class.new(source: 'org/repo', tile: 'tile.json', always_loaded: true, depends_on: [])
      expect(pack.always_loaded?).to be(true)
    end

    it 'returns false when always_loaded is false' do
      pack = described_class.new(source: 'org/repo', tile: 'tile.json', always_loaded: false, depends_on: [])
      expect(pack.always_loaded?).to be(false)
    end
  end
end
