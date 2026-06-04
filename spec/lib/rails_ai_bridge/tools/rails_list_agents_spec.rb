# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::RailsListAgents do
  let(:agent_summaries) do
    [
      RailsAiBridge::Registry::SkillSummary.new(
        name: 'code-reviewer',
        pack: 'rails',
        description: 'Automated code review agent'
      ),
      RailsAiBridge::Registry::SkillSummary.new(
        name: 'test-generator',
        pack: 'core',
        description: 'Test generation agent'
      )
    ]
  end
  let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
  let(:response) { described_class.call }
  let(:content) { response.content.first[:text] }

  before do
    allow(resolver).to receive(:list_agents).and_return(agent_summaries)
    allow(described_class).to receive(:registry_resolver).and_return(resolver)
  end

  describe '.call' do
    context 'when agents are available' do
      it 'returns a formatted markdown string with all agents' do
        expect(content).to include('# Available Agents')
        expect(content).to include('- **code-reviewer** (from rails)')
        expect(content).to include('  Automated code review agent')
        expect(content).to include('- **test-generator** (from core)')
        expect(content).to include('  Test generation agent')
      end

      it 'sorts agents alphabetically by name' do
        code_reviewer_idx = content.index('code-reviewer')
        test_generator_idx = content.index('test-generator')
        expect(code_reviewer_idx).to be < test_generator_idx
      end
    end

    context 'when no agents are available' do
      let(:agent_summaries) { [] }

      it 'returns a message indicating no agents' do
        expect(content).to include('No agents available')
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
