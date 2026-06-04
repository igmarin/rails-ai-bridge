# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::RailsListPacks do
  let(:tile_manifest) do
    instance_double(RailsAiBridge::Registry::TileManifest, skills: {}, agents: {}, deprecated_skills: {}, depends_on: [])
  end
  let(:loaded_packs) do
    [
      RailsAiBridge::Registry::LoadedPack.new(
        name: 'rails',
        tile: tile_manifest,
        base_path: '/path/to/rails',
        priority: 10
      ),
      RailsAiBridge::Registry::LoadedPack.new(
        name: 'core',
        tile: tile_manifest,
        base_path: '/path/to/core',
        priority: 20
      ),
      RailsAiBridge::Registry::LoadedPack.new(
        name: 'local_0',
        tile: tile_manifest,
        base_path: '/path/to/local',
        priority: 0
      )
    ]
  end
  let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
  let(:response) { described_class.call }
  let(:content) { response.content.first[:text] }

  before do
    allow(resolver).to receive(:active_packs).and_return(loaded_packs)
    allow(described_class).to receive(:registry_resolver).and_return(resolver)
  end

  describe '.call' do
    context 'when packs are available' do
      it 'returns a formatted markdown string with all packs sorted by priority' do
        expect(content).to include('# Loaded Packs')
        expect(content).to include('- **local_0** (priority: 0)')
        expect(content).to include('- **rails** (priority: 10)')
        expect(content).to include('- **core** (priority: 20)')
      end

      it 'sorts packs by priority ascending (highest priority first)' do
        lines = content.split("\n")
        local_idx = lines.index { |l| l.include?('local_0') }
        rails_idx = lines.index { |l| l.include?('rails') }
        core_idx = lines.index { |l| l.include?('core') }

        expect(local_idx).to be < rails_idx
        expect(rails_idx).to be < core_idx
      end
    end

    context 'when no packs are available' do
      let(:loaded_packs) { [] }

      it 'returns a message indicating no packs' do
        expect(content).to include('No packs loaded')
      end
    end

    context 'when registry resolver is not available' do
      before do
        allow(described_class).to receive(:registry_resolver).and_return(nil)
      end

      it 'returns an error message' do
        expect(content).to include('Registry resolution not available')
      end
    end
  end
end
