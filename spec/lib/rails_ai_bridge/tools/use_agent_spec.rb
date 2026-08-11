# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::UseAgent do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }

  def build_resolved(name:, pack:, path:, content:)
    RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: path, content: content)
  end

  # ── no manifest ────────────────────────────────────────────────────────────

  describe 'when manifest is missing' do
    let(:params) { { name: 'tdd-workflow' } }

    before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

    it 'mentions the registry manifest' do
      expect(content).to include('registry manifest')
    end
  end

  # ── agent found ────────────────────────────────────────────────────────────

  describe 'when the agent is found' do
    let(:params)   { { name: 'tdd-workflow' } }
    let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
    let(:agent) do
      build_resolved(name: 'tdd-workflow', pack: 'core',
                     path: '/cache/core/agents/tdd-workflow.md',
                     content: "# TDD Workflow\n\nRed, green, refactor.")
    end

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_agent).with('tdd-workflow').and_return(agent)
    end

    it 'frames the output as an activation directive' do
      expect(content).to include('Activating agent: tdd-workflow')
    end

    it 'names the source pack' do
      expect(content).to include('core')
    end

    it 'includes the full agent content' do
      expect(content).to include(agent.content)
    end

    it 'ends with a follow-through instruction for workflows' do
      expect(content).to include('end to end')
    end
  end

  # ── agent not found ────────────────────────────────────────────────────────

  describe 'when the agent is not found' do
    let(:params)   { { name: 'nonexistent-agent' } }
    let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_agent).with('nonexistent-agent').and_return(nil)
    end

    it 'mentions the agent name' do
      expect(content).to include('nonexistent-agent')
    end

    it 'suggests using rails_list_registry with the agents type' do
      expect(content).to include('rails_list_registry type=agents')
    end
  end
end
