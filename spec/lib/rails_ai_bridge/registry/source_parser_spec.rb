# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::SourceParser do
  describe '.parse' do
    subject(:parsed) { described_class.parse(source) }

    # ── local paths ─────────────────────────────────────────────────────────

    context 'with an absolute local path' do
      let(:source) { '/Users/alice/skills/my-pack' }

      it { is_expected.to have_attributes(type: :local_path, resolved_url: source) }
    end

    context 'with a relative ./ path' do
      let(:source) { './local/skills' }

      it { is_expected.to have_attributes(type: :local_path, resolved_url: source) }
    end

    context 'with a relative ../ path' do
      let(:source) { '../shared/skills' }

      it { is_expected.to have_attributes(type: :local_path, resolved_url: source) }
    end

    # ── full git URLs ────────────────────────────────────────────────────────

    context 'with an https:// git URL' do
      let(:source) { 'https://github.com/myorg/my-skills.git' }

      it { is_expected.to have_attributes(type: :git_url, resolved_url: source) }
    end

    context 'with an https:// URL without .git suffix' do
      let(:source) { 'https://gitlab.com/myorg/skills' }

      it { is_expected.to have_attributes(type: :git_url, resolved_url: source) }
    end

    context 'with a git@ SSH URL' do
      let(:source) { 'git@github.com:myorg/my-skills.git' }

      it { is_expected.to have_attributes(type: :git_url, resolved_url: source) }
    end

    # ── GitHub shorthand ────────────────────────────────────────────────────

    context 'with owner/repo shorthand' do
      let(:source) { 'igmarin/ruby-core-skills' }

      it { is_expected.to have_attributes(type: :github_shorthand) }

      it 'expands to a github https URL' do
        expect(parsed.resolved_url).to eq('https://github.com/igmarin/ruby-core-skills.git')
      end
    end

    context 'with owner/repo containing dots and underscores' do
      let(:source) { 'my-org/my_pack.v2' }

      it { is_expected.to have_attributes(type: :github_shorthand) }
    end

    # ── invalid formats ─────────────────────────────────────────────────────

    context 'with a bare word (no slashes)' do
      let(:source) { 'not-a-source' }

      it 'raises ResolutionError naming the three valid forms' do
        expect { parsed }.to raise_error(
          RailsAiBridge::Registry::SkillSourceResolver::ResolutionError,
          %r{local path.*https?://.*owner/repo}im
        )
      end
    end

    context 'with empty string' do
      let(:source) { '' }

      it 'raises ResolutionError' do
        expect { parsed }.to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError)
      end
    end

    context 'with too many path segments' do
      let(:source) { 'org/repo/extra' }

      it 'raises ResolutionError' do
        expect { parsed }.to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError)
      end
    end
  end
end
