# frozen_string_literal: true

require 'spec_helper'
require 'generators/rails_ai_bridge/install/profile_resolver'

RSpec.describe RailsAiBridge::Generators::ProfileResolver do
  let(:shell) { double('shell', say: nil, ask: 'custom') }

  describe '#call — option given via CLI' do
    it 'returns the profile name for a valid option' do
      expect(described_class.new('minimal', shell: shell).call).to eq('minimal')
    end

    it 'normalises uppercase input' do
      expect(described_class.new('FULL', shell: shell).call).to eq('full')
    end

    it 'returns custom and warns for an unknown option' do
      resolver = described_class.new('bogus', shell: shell)
      allow(shell).to receive(:say)
      result = resolver.call
      expect(result).to eq('custom')
      expect(shell).to have_received(:say).with("Unknown profile 'bogus'. Falling back to custom.", :yellow)
    end
  end

  describe '#call — interactive (no option)' do
    before { allow(shell).to receive(:say) }

    it 'asks the user when option is nil' do
      allow(shell).to receive(:ask).with('Choose profile (default: custom):').and_return('minimal')
      expect(described_class.new(nil, shell: shell).call).to eq('minimal')
    end

    it 'defaults to custom when the user presses enter' do
      allow(shell).to receive(:ask).and_return('')
      expect(described_class.new(nil, shell: shell).call).to eq('custom')
    end

    it 'shows the available profiles before asking' do
      allow(shell).to receive(:ask).and_return('')
      described_class.new(nil, shell: shell).call
      described_class::PROFILE_OPTIONS.each_key do |key|
        expect(shell).to have_received(:say).with(a_string_including(key))
      end
    end
  end

  describe '.formats_for' do
    it 'returns the format list for minimal' do
      expect(described_class.formats_for('minimal')).to eq(%i[claude cursor windsurf copilot gemini])
    end

    it 'returns an empty array for mcp' do
      expect(described_class.formats_for('mcp')).to eq([])
    end

    it 'returns a dup so callers cannot mutate the registry' do
      a = described_class.formats_for('minimal')
      b = described_class.formats_for('minimal')
      a << :extra
      expect(b).not_to include(:extra)
    end
  end

  describe '.split_rules_for' do
    it 'returns false for minimal' do
      expect(described_class.split_rules_for('minimal')).to be false
    end

    it 'returns true for full' do
      expect(described_class.split_rules_for('full')).to be true
    end
  end

  describe '.description_for' do
    it 'returns a non-empty string for each profile' do
      described_class::PROFILE_OPTIONS.each_key do |key|
        expect(described_class.description_for(key)).to be_a(String).and be_present
      end
    end
  end
end
