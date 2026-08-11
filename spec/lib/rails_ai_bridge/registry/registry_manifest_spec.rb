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

    context 'with context_providers present' do
      let(:minimal_json) do
        super().merge(
          'context_providers' => {
            'app_mcp' => {
              'type' => 'mcp',
              'endpoint' => 'http://localhost:3000/mcp',
              'optional' => true,
              'tools' => ['rails_get_schema', { 'name' => 'rails_get_model_details', 'field' => 'models' }]
            }
          }
        )
      end

      it 'parses providers into ContextProviderDefinition instances' do
        provider = manifest.context_providers['app_mcp']
        expect(provider).to be_a(RailsAiBridge::Registry::ContextProviderDefinition)
        expect(provider.type).to eq('mcp')
        expect(provider.endpoint).to eq('http://localhost:3000/mcp')
      end

      it 'parses each tool into a ContextToolSpec' do
        tools = manifest.context_providers['app_mcp'].tools
        expect(tools.length).to eq(2)
        expect(tools.first).to be_simple
        expect(tools.last).to be_mapped
      end
    end

    context 'without context_providers' do
      it 'defaults context_providers to an empty hash' do
        expect(manifest.context_providers).to eq({})
      end
    end
  end

  describe '.new' do
    it 'defaults context_providers when the keyword is omitted (backward compatibility)' do
      manifest = described_class.new(version: '1.0.0', packs: {}, default_stack: [])
      expect(manifest.context_providers).to eq({})
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

  describe '.validate!' do
    subject(:validate) { described_class.validate!(json) }

    context 'with a valid minimal manifest' do
      let(:json) { minimal_json }

      it 'returns the data without raising' do
        expect { validate }.not_to raise_error
      end
    end

    context 'with an empty manifest' do
      let(:json) { {} }

      it 'is valid (no required top-level keys)' do
        expect { validate }.not_to raise_error
      end
    end

    context 'with every optional key populated' do
      let(:json) do
        {
          'version' => '2.0.0',
          'packs' => {
            'core' => {
              'source' => 'igmarin/ruby-core-skills',
              'ref' => 'main',
              'tile' => 'tile.json',
              'depends_on' => %w[rails planning],
              'always_loaded' => true,
              'priority' => 10
            }
          },
          'default_stack' => %w[core]
        }
      end

      it 'is valid' do
        expect { validate }.not_to raise_error
      end
    end

    context 'when the root is not a Hash' do
      let(:json) { %w[not a hash] }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /root.*Hash/i
        )
      end
    end

    context 'when version is not a String' do
      let(:json) { minimal_json.merge('version' => 1) }

      it 'raises ValidationError naming the field' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /version.*String/i
        )
      end
    end

    context 'when packs is not a Hash' do
      let(:json) { minimal_json.merge('packs' => []) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /packs.*Hash/i
        )
      end
    end

    context 'when default_stack is not an Array of Strings' do
      let(:json) { minimal_json.merge('default_stack' => ['core', 42]) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /default_stack/i
        )
      end
    end

    context 'when a pack entry is not a Hash' do
      let(:json) { minimal_json.merge('packs' => { 'core' => 'not-a-hash' }) }

      it 'raises ValidationError naming the pack' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*Hash/i
        )
      end
    end

    context 'when a pack is missing source' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'tile' => 'tile.json' } }) }

      it 'raises ValidationError naming the pack and key' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*source/i
        )
      end
    end

    context 'when a pack source is an empty String' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => '' } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*source.*non-empty/i
        )
      end
    end

    context 'when a pack source is not a String' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 123 } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*source.*String/i
        )
      end
    end

    context 'when depends_on is not an Array' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 'x/y', 'depends_on' => 'rails' } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*depends_on.*Array/i
        )
      end
    end

    context 'when depends_on contains a non-String' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 'x/y', 'depends_on' => [:rails] } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*depends_on.*String/i
        )
      end
    end

    context 'when ref is not a String' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 'x/y', 'ref' => 1 } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*ref.*String/i
        )
      end
    end

    context 'when always_loaded is not a boolean' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 'x/y', 'always_loaded' => 'yes' } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*always_loaded.*boolean/i
        )
      end
    end

    context 'when priority is not an Integer' do
      let(:json) { minimal_json.merge('packs' => { 'core' => { 'source' => 'x/y', 'priority' => 'high' } }) }

      it 'raises ValidationError' do
        expect { validate }.to raise_error(
          RailsAiBridge::Registry::RegistryManifest::ValidationError, /pack 'core'.*priority.*Integer/i
        )
      end
    end

    it 'reports only the first invalid field' do
      json = minimal_json.merge(
        'version' => 1,
        'packs' => { 'core' => { 'source' => 123 } }
      )

      expect { described_class.validate!(json) }.to raise_error(
        RailsAiBridge::Registry::RegistryManifest::ValidationError
      ) { |error| expect(error.message).not_to include('source') }
    end
  end
end
