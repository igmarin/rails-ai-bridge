# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'tmpdir'

RSpec.describe RailsAiBridge::AssistantFormatsPreference do
  let(:tmpdir)   { Dir.mktmpdir }
  let(:yml_path) { Pathname.new(File.join(tmpdir, 'config/rails_ai_bridge/install.yml')) }

  before do
    allow(described_class).to receive(:config_path).and_return(yml_path)
  end

  after { FileUtils.remove_entry(tmpdir) }

  describe '.formats_for_default_bridge_task' do
    context 'when install.yml does not exist' do
      it 'returns nil (fall back to all formats)' do
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    context 'when install.yml is present with valid formats' do
      before do
        yml_path.dirname.mkpath
        File.write(yml_path, YAML.dump({ 'formats' => %w[claude codex] }))
      end

      it 'returns the configured formats as symbols' do
        expect(described_class.formats_for_default_bridge_task).to eq(%i[claude codex])
      end

      it 'ignores unknown format keys' do
        File.write(yml_path, YAML.dump({ 'formats' => %w[claude unknown_tool] }))
        expect(described_class.formats_for_default_bridge_task).to eq(%i[claude])
      end

      it 'returns nil when all formats are unknown' do
        File.write(yml_path, YAML.dump({ 'formats' => %w[unknown_a unknown_b] }))
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    context 'when install.yml has an empty formats list' do
      before do
        yml_path.dirname.mkpath
        File.write(yml_path, YAML.dump({ 'formats' => [] }))
      end

      it 'returns nil (fall back to all formats)' do
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    context 'when install.yml is syntactically invalid' do
      before do
        yml_path.dirname.mkpath
        File.write(yml_path, ":\t invalid: yaml: :")
      end

      it 'returns nil gracefully' do
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    context 'when install.yml has no formats key' do
      before do
        yml_path.dirname.mkpath
        File.write(yml_path, YAML.dump({ 'other_key' => 'value' }))
      end

      it 'returns nil' do
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end
  end

  describe '.write!' do
    before { yml_path.dirname.mkpath }

    it 'writes a YAML file with the requested formats' do
      described_class.write!(formats: %i[claude cursor])
      data = YAML.safe_load_file(yml_path)
      expect(data['formats']).to contain_exactly('claude', 'cursor')
    end

    it 'filters out unknown format keys' do
      described_class.write!(formats: %i[claude unknown_tool])
      data = YAML.safe_load_file(yml_path)
      expect(data['formats']).to eq(['claude'])
    end

    it 'accepts string format names' do
      described_class.write!(formats: %w[codex copilot])
      data = YAML.safe_load_file(yml_path)
      expect(data['formats']).to contain_exactly('codex', 'copilot')
    end

    it 'deduplicates formats' do
      described_class.write!(formats: %i[claude claude codex])
      data = YAML.safe_load_file(yml_path)
      expect(data['formats']).to eq(%w[claude codex])
    end

    it 'raises when config_path is nil (Rails app unavailable)' do
      allow(described_class).to receive(:config_path).and_return(nil)
      expect { described_class.write!(formats: %i[claude]) }
        .to raise_error(RailsAiBridge::Error, /Rails app not available/)
    end
  end

  describe 'FORMAT_KEYS' do
    it 'includes all seven supported formats' do
      expect(described_class::FORMAT_KEYS).to contain_exactly(:claude, :codex, :cursor, :windsurf, :copilot, :json,
                                                              :gemini)
    end
  end
end
