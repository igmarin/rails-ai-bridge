# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::RailsListSkills do
  let(:skill_summaries) do
    [
      RailsAiBridge::Registry::SkillSummary.new(
        name: 'tdd',
        pack: 'rails',
        description: 'Test-driven development workflow'
      ),
      RailsAiBridge::Registry::SkillSummary.new(
        name: 'refactor',
        pack: 'core',
        description: 'Code refactoring patterns'
      )
    ]
  end
  let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
  let(:response) { described_class.call }
  let(:content) { response.content.first[:text] }

  before do
    allow(resolver).to receive(:list_skills).and_return(skill_summaries)
    allow(described_class).to receive(:registry_resolver).and_return(resolver)
  end

  describe '.call' do
    context 'when skills are available' do
      it 'returns a formatted markdown string with all skills' do
        expect(content).to include('# Available Skills')
        expect(content).to include('- **tdd** (from rails)')
        expect(content).to include('  Test-driven development workflow')
        expect(content).to include('- **refactor** (from core)')
        expect(content).to include('  Code refactoring patterns')
      end

      it 'sorts skills alphabetically by name' do
        tdd_idx = content.index('tdd')
        refactor_idx = content.index('refactor')
        expect(tdd_idx).to be < refactor_idx
      end
    end

    context 'when no skills are available' do
      let(:skill_summaries) { [] }

      it 'returns a message indicating no skills' do
        expect(content).to include('No skills available')
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
