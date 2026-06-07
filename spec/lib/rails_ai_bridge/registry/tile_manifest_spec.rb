# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::TileManifest do
  let(:full_json) do
    {
      'name' => 'ruby-core-skills',
      'version' => '1.2.0',
      'summary' => 'Core Ruby skills',
      'depends_on' => [],
      'skills' => {
        'code-review' => {
          'path' => 'skills/code_review.md',
          'description' => 'Review Ruby code',
          'tags' => %w[ruby review]
        },
        'tdd' => {
          'path' => 'skills/tdd.md'
        }
      },
      'agents' => {
        'rails-agent' => {
          'path' => 'agents/rails_agent.md',
          'description' => 'Full Rails agent',
          'depends_on' => ['code-review']
        }
      },
      'deprecated_skills' => {
        'old-review' => {
          'moved_to' => 'code-review',
          'message' => 'Use code-review instead',
          'removed_in' => 'v2.0.0'
        }
      }
    }
  end

  describe '.from_json' do
    subject(:tile) { described_class.from_json(full_json) }

    it 'parses name' do
      expect(tile.name).to eq('ruby-core-skills')
    end

    it 'parses version' do
      expect(tile.version).to eq('1.2.0')
    end

    it 'parses summary' do
      expect(tile.summary).to eq('Core Ruby skills')
    end

    it 'parses depends_on' do
      expect(tile.depends_on).to eq([])
    end

    it 'parses skills as SkillEntry instances' do
      expect(tile.skills['code-review']).to be_a(RailsAiBridge::Registry::SkillEntry)
    end

    it 'parses skill path' do
      expect(tile.skills['code-review'].path).to eq('skills/code_review.md')
    end

    it 'parses skill description' do
      expect(tile.skills['code-review'].description).to eq('Review Ruby code')
    end

    it 'parses skill tags' do
      expect(tile.skills['code-review'].tags).to eq(%w[ruby review])
    end

    it 'defaults missing description to nil' do
      expect(tile.skills['tdd'].description).to be_nil
    end

    it 'defaults missing tags to empty array' do
      expect(tile.skills['tdd'].tags).to eq([])
    end

    it 'parses agents as AgentEntry instances' do
      expect(tile.agents['rails-agent']).to be_a(RailsAiBridge::Registry::AgentEntry)
    end

    it 'parses agent path' do
      expect(tile.agents['rails-agent'].path).to eq('agents/rails_agent.md')
    end

    it 'parses agent description' do
      expect(tile.agents['rails-agent'].description).to eq('Full Rails agent')
    end

    it 'parses agent depends_on' do
      expect(tile.agents['rails-agent'].depends_on).to eq(['code-review'])
    end

    it 'parses deprecated_skills as DeprecatedEntry instances' do
      expect(tile.deprecated_skills['old-review']).to be_a(RailsAiBridge::Registry::DeprecatedEntry)
    end

    it 'parses deprecated moved_to' do
      expect(tile.deprecated_skills['old-review'].moved_to).to eq('code-review')
    end

    it 'parses deprecated message' do
      expect(tile.deprecated_skills['old-review'].message).to eq('Use code-review instead')
    end

    it 'parses deprecated removed_in' do
      expect(tile.deprecated_skills['old-review'].removed_in).to eq('v2.0.0')
    end

    context 'when agents key is absent' do
      before { full_json.delete('agents') }

      it 'defaults agents to empty hash' do
        expect(tile.agents).to eq({})
      end
    end

    context 'when deprecated_skills key is absent' do
      before { full_json.delete('deprecated_skills') }

      it 'defaults deprecated_skills to empty hash' do
        expect(tile.deprecated_skills).to eq({})
      end
    end

    context 'when summary is absent' do
      before { full_json.delete('summary') }

      it 'defaults summary to nil' do
        expect(tile.summary).to be_nil
      end
    end

    context 'when depends_on is absent' do
      before { full_json.delete('depends_on') }

      it 'defaults depends_on to empty array' do
        expect(tile.depends_on).to eq([])
      end
    end
  end

  describe '.from_file' do
    let(:path) do
      file = Tempfile.new(['tile', '.json'])
      file.write(JSON.generate(full_json))
      file.close
      file.path
    end

    after { FileUtils.rm_f(path) }

    it 'loads and parses the file' do
      expect(described_class.from_file(path).name).to eq('ruby-core-skills')
    end

    it 'raises ArgumentError for a non-existent path' do
      expect { described_class.from_file('/nonexistent/tile.json') }
        .to raise_error(ArgumentError, /could not be read/)
    end

    it 'raises ArgumentError for invalid JSON' do
      file = Tempfile.new(['tile', '.json'])
      file.write('{ not valid json }')
      file.close

      expect { described_class.from_file(file.path) }
        .to raise_error(ArgumentError, /invalid JSON/)
    ensure
      file&.unlink
    end
  end

  describe '.from_json (missing required fields)' do
    context 'when name key is missing' do
      it 'raises ArgumentError naming the missing field' do
        json = full_json.except('name')

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /name/)
      end
    end

    context 'when version key is missing' do
      it 'raises ArgumentError naming the missing field' do
        json = full_json.except('version')

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /version/)
      end
    end

    context 'when a skill entry is missing its path key' do
      it 'raises ArgumentError naming the missing field' do
        json = full_json.merge('skills' => { 'bad-skill' => { 'description' => 'oops' } })

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /path/)
      end
    end

    context 'when an agent entry is missing its path key' do
      it 'raises ArgumentError naming the missing field' do
        json = full_json.merge('agents' => { 'bad-agent' => { 'description' => 'oops' } })

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /path/)
      end
    end

    context 'when a deprecated entry is missing its moved_to key' do
      it 'raises ArgumentError naming the missing field' do
        json = full_json.merge('deprecated_skills' => { 'old' => { 'message' => 'gone' } })

        expect { described_class.from_json(json) }
          .to raise_error(ArgumentError, /moved_to/)
      end
    end
  end
end

RSpec.describe RailsAiBridge::Registry::DeprecatedEntry do
  describe '#removed_in?' do
    it 'returns true when removed_in is set' do
      entry = described_class.new(moved_to: 'new-skill', message: 'use new-skill', removed_in: 'v2.0.0')
      expect(entry.removed_in?).to be(true)
    end

    it 'returns false when removed_in is nil' do
      entry = described_class.new(moved_to: 'new-skill', message: 'use new-skill', removed_in: nil)
      expect(entry.removed_in?).to be(false)
    end
  end
end
