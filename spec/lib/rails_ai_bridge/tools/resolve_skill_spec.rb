# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::ResolveSkill do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }

  def build_resolved(name:, pack:, path:, content:)
    RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: path, content: content)
  end

  def build_resolver(**stubs)
    defaults = { resolve_skill: nil, resolve_agent: nil, list_skills: [], list_agents: [], active_packs: [] }
    instance_double(RailsAiBridge::Registry::Resolver, **defaults, **stubs)
  end

  # ── no manifest ────────────────────────────────────────────────────────────

  describe 'when manifest is missing' do
    let(:params) { { name: 'code-review' } }

    before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

    it 'mentions registry manifest' do
      expect(content).to include('registry manifest')
    end

    it 'includes the configured manifest path' do
      expect(content).to include('config/rails_ai_bridge_registry.json')
    end
  end

  # ── skill found ────────────────────────────────────────────────────────────

  describe 'when the skill is found' do
    let(:params)   { { name: 'code-review' } }
    let(:resolver) { build_resolver }
    let(:skill) do
      build_resolved(name: 'code-review', pack: 'rails',
                     path: '/cache/rails/code-review/SKILL.md',
                     content: "# Code Review\n\nReview Rails PRs.")
    end

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
    end

    it 'includes the skill name as a header' do
      expect(content).to include('# code-review')
    end

    it 'includes the pack name' do
      expect(content).to include('rails')
    end

    it 'includes the full skill content' do
      expect(content).to include(skill.content)
    end
  end

  # ── skill not found ────────────────────────────────────────────────────────

  describe 'when the skill is not found' do
    let(:params)   { { name: 'nonexistent-skill' } }
    let(:resolver) { build_resolver }

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_skill).with('nonexistent-skill').and_return(nil)
    end

    it 'mentions the skill name' do
      expect(content).to include('nonexistent-skill')
    end

    it 'suggests using rails_list_registry' do
      expect(content).to include('rails_list_registry')
    end
  end

  # ── agent found ────────────────────────────────────────────────────────────

  describe 'when resolving an agent' do
    let(:params)   { { name: 'tdd-workflow', type: 'agent' } }
    let(:resolver) { build_resolver }
    let(:agent) do
      build_resolved(name: 'tdd-workflow', pack: 'rails',
                     path: '/cache/rails/tdd-workflow/AGENT.md',
                     content: "# TDD Workflow\n\nFull TDD cycle.")
    end

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_agent).with('tdd-workflow').and_return(agent)
    end

    it 'includes the agent name as a header' do
      expect(content).to include('# tdd-workflow')
    end

    it 'includes the full agent content' do
      expect(content).to include(agent.content)
    end
  end

  # ── agent not found ────────────────────────────────────────────────────────

  describe 'when the agent is not found' do
    let(:params)   { { name: 'missing-agent', type: 'agent' } }
    let(:resolver) { build_resolver }

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_agent).with('missing-agent').and_return(nil)
    end

    it 'mentions the agent name' do
      expect(content).to include('missing-agent')
    end

    it 'suggests using rails_list_registry' do
      expect(content).to include('rails_list_registry')
    end
  end

  # ── pack-pinned resolution ─────────────────────────────────────────────────

  describe 'with pack filter' do
    let(:loaded_pack) do
      instance_double(RailsAiBridge::Registry::LoadedPack,
                      name: 'rails', tile: double(skills: {}, agents: {}),
                      base_path: '/cache/rails', priority: 10)
    end

    def summary(name: 'code-review', pack: 'rails', description: 'Review.')
      RailsAiBridge::Registry::SkillSummary.new(name: name, pack: pack, description: description)
    end

    context 'when the skill exists in the requested pack' do
      let(:params)   { { name: 'code-review', pack: 'rails' } }
      let(:resolver) { build_resolver(active_packs: [loaded_pack], list_skills: [summary]) }
      let(:skill) do
        build_resolved(name: 'code-review', pack: 'rails',
                       path: '/cache/rails/code-review/SKILL.md',
                       content: "# Code Review\n\nReview Rails PRs.")
      end

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        single_resolver = instance_double(RailsAiBridge::Registry::Resolver)
        allow(RailsAiBridge::Registry::Resolver).to receive(:new).with([loaded_pack]).and_return(single_resolver)
        allow(single_resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
      end

      it 'returns the skill content' do
        expect(content).to include(skill.content)
      end
    end

    context 'when the skill is not in the requested pack but exists elsewhere' do
      let(:params)   { { name: 'code-review', pack: 'nonexistent' } }
      let(:resolver) { build_resolver(active_packs: [], list_skills: [summary]) }
      let(:fallback) do
        build_resolved(name: 'code-review', pack: 'rails',
                       path: '/cache/rails/code-review/SKILL.md',
                       content: "# Code Review\n\nReview Rails PRs.")
      end

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(fallback)
      end

      it 'falls back to priority-based resolution and includes the pack name' do
        expect(content).to include('rails')
      end
    end
  end

  # ── tool registration ──────────────────────────────────────────────────────

  describe 'tool metadata' do
    it 'has the correct tool name' do
      expect(described_class.tool_name).to eq('rails_resolve_skill')
    end

    it 'is registered in the server TOOLS list' do
      expect(RailsAiBridge::Server::TOOLS).to include(described_class)
    end
  end
end
