# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/registry/resolver'

RSpec.describe RailsAiBridge::Registry::RakePresenter do
  # Minimal stand-ins so we do not need real pack fixtures.
  subject(:presenter) { described_class.new(resolver) }

  let(:skill_summary) do
    RailsAiBridge::Registry::SkillSummary.new(
      name: 'code-review',
      pack: 'rails',
      description: 'Review Rails code against team conventions.'
    )
  end

  let(:resolved_skill) do
    RailsAiBridge::Registry::ResolvedSkill.new(
      name: 'code-review',
      pack: 'rails',
      path: 'skills/code-review.md',
      content: "# Code Review\nReview your Rails code."
    )
  end

  let(:resolver) { instance_double(RailsAiBridge::Registry::Resolver) }

  describe '#skills_table' do
    context 'when skills are present' do
      before { allow(resolver).to receive(:list_skills).and_return([skill_summary]) }

      it 'includes a header with the skill count' do
        expect(presenter.skills_table).to include('Available Skills (1)')
      end

      it 'includes the skill name' do
        expect(presenter.skills_table).to include('code-review')
      end

      it 'includes the pack name' do
        expect(presenter.skills_table).to include('rails')
      end

      it 'includes the description' do
        expect(presenter.skills_table).to include('Review Rails code')
      end

      it 'includes column headers' do
        output = presenter.skills_table
        expect(output).to include('Skill')
        expect(output).to include('Pack')
        expect(output).to include('Description')
      end

      it 'includes a separator line' do
        expect(presenter.skills_table).to include('-' * 20)
      end
    end

    context 'when no skills are loaded' do
      before { allow(resolver).to receive(:list_skills).and_return([]) }

      it 'returns a helpful empty message' do
        expect(presenter.skills_table).to include('No skills are loaded')
      end
    end

    context 'when a description exceeds the truncation limit' do
      let(:long_skill) do
        RailsAiBridge::Registry::SkillSummary.new(
          name: 'long-skill',
          pack: 'core',
          description: 'A' * 100
        )
      end

      before { allow(resolver).to receive(:list_skills).and_return([long_skill]) }

      it 'truncates the description with an ellipsis' do
        output = presenter.skills_table
        expect(output).to include('…')
        expect(output).not_to include('A' * 100)
      end
    end
  end

  describe '#resolve_skill_output' do
    context 'when the skill exists and no deprecation or pack mismatch' do
      before do
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(resolved_skill)
        allow(resolver).to receive(:check_deprecated).with('code-review').and_return(nil)
      end

      it 'includes the skill name header' do
        expect(presenter.resolve_skill_output('code-review')).to include('# code-review')
      end

      it 'includes the pack name' do
        expect(presenter.resolve_skill_output('code-review')).to include('rails')
      end

      it 'includes the file path' do
        expect(presenter.resolve_skill_output('code-review')).to include('skills/code-review.md')
      end

      it 'includes the full skill content' do
        expect(presenter.resolve_skill_output('code-review')).to include('# Code Review')
      end

      it 'does not include a WARNING line' do
        expect(presenter.resolve_skill_output('code-review')).not_to include('WARNING')
      end

      it 'does not include an INFO line when no pack was requested' do
        expect(presenter.resolve_skill_output('code-review')).not_to include('INFO')
      end
    end

    context 'when the skill has a deprecation warning' do
      before do
        allow(resolver).to receive(:resolve_skill).with('old-review').and_return(resolved_skill)
        allow(resolver).to receive(:check_deprecated).with('old-review')
                                                     .and_return("'old-review' is deprecated. Use 'code-review' instead.")
      end

      it 'prefixes the output with a WARNING line' do
        output = presenter.resolve_skill_output('old-review')
        expect(output).to start_with('WARNING:')
        expect(output).to include('deprecated')
      end
    end

    context 'when the resolved pack differs from the requested pack' do
      before do
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(resolved_skill)
        allow(resolver).to receive(:check_deprecated).with('code-review').and_return(nil)
      end

      it 'includes an INFO line about the mismatch' do
        output = presenter.resolve_skill_output('code-review', requested_pack: 'core')
        expect(output).to include('INFO:')
        expect(output).to include("resolved from pack 'rails'")
        expect(output).to include("requested pack: 'core'")
      end
    end

    context 'when requested_pack matches the resolved pack' do
      before do
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(resolved_skill)
        allow(resolver).to receive(:check_deprecated).with('code-review').and_return(nil)
      end

      it 'does not include an INFO line' do
        output = presenter.resolve_skill_output('code-review', requested_pack: 'rails')
        expect(output).not_to include('INFO:')
      end
    end

    context 'when the skill is not found' do
      before do
        allow(resolver).to receive(:resolve_skill).with('missing-skill').and_return(nil)
      end

      it 'returns a not-found message' do
        output = presenter.resolve_skill_output('missing-skill')
        expect(output).to include("Skill 'missing-skill' not found")
      end

      it 'hints to run the list task' do
        output = presenter.resolve_skill_output('missing-skill')
        expect(output).to include('rails ai:skills:list')
      end
    end
  end

  describe '.no_manifest_message' do
    it 'returns a string containing the given path' do
      msg = described_class.no_manifest_message('/config/registry.json')
      expect(msg).to include('/config/registry.json')
    end

    it 'includes a reference to the setup guide' do
      msg = described_class.no_manifest_message('/any/path.json')
      expect(msg).to include('skill-registry-guide.md')
    end
  end
end
