# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/registry/tile_manifest'

RSpec.describe RailsAiBridge::Tools::ListRegistry do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }

  def build_tile(name:, version:, summary:)
    RailsAiBridge::Registry::TileManifest.new(
      name: name,
      version: version,
      summary: summary,
      depends_on: [],
      skills: {},
      agents: {},
      deprecated_skills: {}
    )
  end

  # ── setup message (no manifest) ────────────────────────────────────────────

  shared_examples 'returns setup message' do
    before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

    it 'mentions registry manifest' do
      expect(content).to include('registry manifest')
    end

    it 'mentions the default manifest path' do
      expect(content).to include('config/rails_ai_bridge_registry.json')
    end

    it 'includes a quick-start JSON snippet' do
      expect(content).to include('"version"')
    end
  end

  # ── type: skills ────────────────────────────────────────────────────────────

  describe 'type: skills' do
    context 'when manifest is missing' do
      let(:params) { { type: 'skills' } }

      it_behaves_like 'returns setup message'
    end

    context 'when skills are available' do
      let(:skills) do
        [
          RailsAiBridge::Registry::SkillSummary.new(name: 'code-review',  pack: 'rails', description: 'Review Rails code.'),
          RailsAiBridge::Registry::SkillSummary.new(name: 'write-tests',  pack: 'core',  description: 'Write RSpec tests.')
        ]
      end
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, list_skills: skills) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      context 'with no pack filter' do
        let(:params) { { type: 'skills' } }

        it 'returns a markdown header' do
          expect(content).to include('# Available Skills')
        end

        it 'lists all skills with name and pack' do
          expect(content).to include('code-review')
          expect(content).to include('rails')
          expect(content).to include('write-tests')
          expect(content).to include('core')
        end

        it 'includes descriptions' do
          expect(content).to include('Review Rails code.')
        end
      end

      context 'with a matching pack filter' do
        let(:params) { { type: 'skills', pack: 'rails' } }

        it 'shows only skills from that pack' do
          expect(content).to include('code-review')
          expect(content).not_to include('write-tests')
        end
      end

      context 'with a non-matching pack filter' do
        let(:params) { { type: 'skills', pack: 'hanami' } }

        it 'returns a no-skills-found message naming the pack' do
          expect(content).to include('No skills found')
          expect(content).to include('hanami')
        end
      end
    end

    context 'when resolver has no skills' do
      let(:params) { { type: 'skills' } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, list_skills: []) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'returns an empty message' do
        expect(content).to include('No skills')
      end
    end
  end

  # ── type: agents ────────────────────────────────────────────────────────────

  describe 'type: agents' do
    context 'when manifest is missing' do
      let(:params) { { type: 'agents' } }

      it_behaves_like 'returns setup message'
    end

    context 'when agents are available' do
      let(:agents) do
        [
          RailsAiBridge::Registry::SkillSummary.new(name: 'tdd-workflow',    pack: 'rails', description: 'Full TDD cycle.'),
          RailsAiBridge::Registry::SkillSummary.new(name: 'review-workflow', pack: 'core',  description: 'PR review cycle.')
        ]
      end
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, list_agents: agents) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      context 'with no pack filter' do
        let(:params) { { type: 'agents' } }

        it 'returns a markdown header' do
          expect(content).to include('# Available Agents')
        end

        it 'lists all agents' do
          expect(content).to include('tdd-workflow')
          expect(content).to include('review-workflow')
        end
      end

      context 'with a matching pack filter' do
        let(:params) { { type: 'agents', pack: 'core' } }

        it 'shows only agents from that pack' do
          expect(content).to include('review-workflow')
          expect(content).not_to include('tdd-workflow')
        end
      end

      context 'with a non-matching pack filter' do
        let(:params) { { type: 'agents', pack: 'hanami' } }

        it 'returns a no-agents-found message naming the pack' do
          expect(content).to include('No agents found')
          expect(content).to include('hanami')
        end
      end
    end

    context 'when resolver has no agents' do
      let(:params) { { type: 'agents' } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, list_agents: []) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'returns an empty message' do
        expect(content).to include('No agents')
      end
    end
  end

  # ── type: packs ─────────────────────────────────────────────────────────────

  describe 'type: packs' do
    context 'when manifest is missing' do
      let(:params) { { type: 'packs' } }

      it_behaves_like 'returns setup message'
    end

    context 'when packs are loaded' do
      let(:active_packs) do
        [
          RailsAiBridge::Registry::LoadedPack.new(
            name: 'rails',
            tile: build_tile(name: 'rails', version: '1.2.0', summary: 'Rails-specific skills.'),
            base_path: '/tmp/rails',
            priority: 10
          ),
          RailsAiBridge::Registry::LoadedPack.new(
            name: 'core',
            tile: build_tile(name: 'core', version: '2.0.0', summary: 'Core Ruby skills.'),
            base_path: '/tmp/core',
            priority: 20
          )
        ]
      end
      let(:params) { { type: 'packs' } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, active_packs: active_packs) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'returns a markdown header' do
        expect(content).to include('# Active Skill Packs')
      end

      it 'shows each pack with name, version, priority, and summary' do
        expect(content).to include('rails').and include('1.2.0').and include('10')
        expect(content).to include('core').and  include('2.0.0').and include('20')
        expect(content).to include('Rails-specific skills.')
      end

      it 'includes total pack count' do
        expect(content).to include('2')
      end

      it 'includes a priority legend' do
        expect(content).to include('Priority:')
      end
    end

    context 'when no packs are loaded' do
      let(:params) { { type: 'packs' } }
      let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver, active_packs: []) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'returns a no-packs message' do
        expect(content).to include('No packs')
      end
    end
  end

  # ── invalid type ────────────────────────────────────────────────────────────

  describe 'invalid type' do
    let(:params) { { type: 'bananas' } }

    before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(double) }

    it 'returns a clear error message' do
      expect(content).to include('Unknown type')
      expect(content).to include('bananas')
      expect(content).to include('skills')
      expect(content).to include('agents')
      expect(content).to include('packs')
    end
  end
end
