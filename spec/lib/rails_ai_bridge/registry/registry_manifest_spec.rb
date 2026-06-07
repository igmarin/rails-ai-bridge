# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::RegistryManifest do
  let(:minimal_json) do
    {
      'version' => '1.0.0',
      'packs' => {
        'core' => {
          'source' => 'igmarin/ruby-core-skills',
          'tile' => 'tile.json',
          'always_loaded' => true
        }
      },
      'default_stack' => %w[core planning]
    }
  end

  describe '.from_json' do
    subject(:manifest) { described_class.from_json(minimal_json) }

    it 'parses version' do
      expect(manifest.version).to eq('1.0.0')
    end

    it 'parses default_stack' do
      expect(manifest.default_stack).to eq(%w[core planning])
    end

    it 'parses packs as PackDefinition instances' do
      expect(manifest.packs['core']).to be_a(RailsAiBridge::Registry::PackDefinition)
    end

    it 'sets pack source' do
      expect(manifest.packs['core'].source).to eq('igmarin/ruby-core-skills')
    end

    it 'sets pack tile' do
      expect(manifest.packs['core'].tile).to eq('tile.json')
    end

    it 'sets always_loaded flag' do
      expect(manifest.packs['core'].always_loaded).to be(true)
    end

    context 'with depends_on on a pack' do
      let(:minimal_json) do
        super().merge(
          'packs' => {
            'rails' => {
              'source' => 'igmarin/rails-agent-skills',
              'tile' => 'tile.json',
              'depends_on' => ['core']
            }
          }
        )
      end

      it 'parses depends_on' do
        expect(manifest.packs['rails'].depends_on).to eq(['core'])
      end
    end

    context 'when always_loaded is absent' do
      it 'defaults always_loaded to false' do
        json = minimal_json.merge('packs' => {
                                    'planning' => { 'source' => 'igmarin/agnostic-planning-skills', 'tile' => 'tile.json' }
                                  })
        m = described_class.from_json(json)
        expect(m.packs['planning'].always_loaded).to be(false)
      end
    end

    context 'when depends_on is absent' do
      it 'defaults depends_on to empty array' do
        expect(manifest.packs['core'].depends_on).to eq([])
      end
    end
  end

  describe '.from_file' do
    subject(:manifest) { described_class.from_file(path) }

    let(:path) do
      file = Tempfile.new(['registry', '.json'])
      file.write(JSON.generate(minimal_json))
      file.close
      file.path
    end

    after { FileUtils.rm_f(path) }

    it 'loads and parses the file' do
      expect(manifest.version).to eq('1.0.0')
    end

    it 'raises ArgumentError for a non-existent path' do
      expect { described_class.from_file('/nonexistent/registry.json') }
        .to raise_error(ArgumentError, /could not be read/)
    end

    it 'raises ArgumentError for invalid JSON' do
      file = Tempfile.new(['registry', '.json'])
      file.write('{ not valid json }')
      file.close

      expect { described_class.from_file(file.path) }
        .to raise_error(ArgumentError, /invalid JSON/)
    ensure
      file&.unlink
    end
  end

  describe '.from_json (missing required fields)' do
    context 'when version key is missing' do
      it 'raises ArgumentError naming the missing field' do
        json = minimal_json.except('version')

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /version/)
      end
    end

    context 'when a pack is missing its source key' do
      it 'raises ArgumentError naming the missing field' do
        json = minimal_json.merge('packs' => { 'core' => { 'tile' => 'tile.json' } })

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /source/)
      end
    end
  end
end
