# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::UseSkill do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }

  def build_resolved(name:, pack:, path:, content:)
    RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: path, content: content)
  end

  # ── no manifest ────────────────────────────────────────────────────────────

  describe 'when manifest is missing' do
    let(:params) { { name: 'code-review' } }

    before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

    it 'mentions the registry manifest' do
      expect(content).to include('registry manifest')
    end

    it 'includes the configured manifest path' do
      expect(content).to include('config/rails_ai_bridge/registry.json')
    end
  end

  # ── skill found ────────────────────────────────────────────────────────────

  describe 'when the skill is found' do
    let(:params)   { { name: 'code-review' } }
    let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
    let(:skill) do
      build_resolved(name: 'code-review', pack: 'rails',
                     path: '/cache/rails/code-review/SKILL.md',
                     content: "# Code Review\n\nReview Rails PRs.")
    end

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
      allow(resolver).to receive(:check_deprecated).with('code-review').and_return(nil)
    end

    it 'frames the output as an application directive' do
      expect(content).to include('Applying skill: code-review')
    end

    it 'names the source pack' do
      expect(content).to include('rails')
    end

    it 'includes the full skill content' do
      expect(content).to include(skill.content)
    end

    it 'ends with a follow-through instruction' do
      expect(content).to include('Work through every step')
    end
  end

  # ── deprecation redirect ───────────────────────────────────────────────────

  describe 'when the skill was deprecated and redirected' do
    let(:params)   { { name: 'review-rails-code' } }
    let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }
    let(:skill) do
      build_resolved(name: 'code-review', pack: 'rails',
                     path: '/cache/rails/code-review/SKILL.md',
                     content: '# Code Review')
    end

    before do
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive(:resolve_skill).with('review-rails-code').and_return(skill)
      allow(resolver).to receive(:check_deprecated).with('review-rails-code')
                                                   .and_return("Skill 'review-rails-code' moved to 'code-review'.")
    end

    it 'surfaces the deprecation warning' do
      expect(content).to include('Deprecated')
      expect(content).to include("moved to 'code-review'")
    end
  end

  # ── skill not found ────────────────────────────────────────────────────────

  describe 'when the skill is not found' do
    let(:params)   { { name: 'nonexistent-skill' } }
    let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

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
end
