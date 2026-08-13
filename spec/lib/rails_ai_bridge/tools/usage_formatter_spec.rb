# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::UsageFormatter do
  # UsageFormatter is a module; include it in an anonymous test double to call its methods.
  let(:formatter) do
    Class.new { include RailsAiBridge::Tools::UsageFormatter }.new
  end

  def build_resolved(name:, pack:, content:)
    RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: "/cache/#{pack}/#{name}.md", content: content)
  end

  describe '#format_usage' do
    let(:resolved) { build_resolved(name: 'code-review', pack: 'rails', content: "# Code Review\n\nReview Rails PRs.") }

    context 'when kind is :skill' do
      it 'generates an intent header with "Applying skill"' do
        result = formatter.format_usage(resolved, kind: :skill)
        expect(result).to start_with('# Applying skill: code-review')
      end

      it 'names the source pack' do
        result = formatter.format_usage(resolved, kind: :skill)
        expect(result).to include('**rails**')
      end

      it 'includes the full content' do
        result = formatter.format_usage(resolved, kind: :skill)
        expect(result).to include(resolved.content)
      end

      it 'ends with the skill follow-through footer' do
        result = formatter.format_usage(resolved, kind: :skill)
        expect(result).to end_with('_Work through every step of this skill in order. If a step does not apply, say so explicitly instead of skipping it silently._')
      end

      it 'separates content from footer with a horizontal rule' do
        result = formatter.format_usage(resolved, kind: :skill)
        expect(result).to include("\n---\n")
      end
    end

    context 'when kind is :agent' do
      it 'generates an intent header with "Activating agent"' do
        result = formatter.format_usage(resolved, kind: :agent)
        expect(result).to start_with('# Activating agent: code-review')
      end

      it 'ends with the agent follow-through footer' do
        result = formatter.format_usage(resolved, kind: :agent)
        expect(result).to end_with('_Follow this workflow end to end and respect its hard gates; do not skip steps silently._')
      end
    end

    context 'with a deprecation warning' do
      it 'includes a deprecation block when warning is provided' do
        result = formatter.format_usage(resolved, kind: :skill, deprecation_warning: 'use code-review-v2 instead')
        expect(result).to include('> **Deprecated:** use code-review-v2 instead')
      end

      it 'does not include a deprecation block when warning is nil' do
        result = formatter.format_usage(resolved, kind: :skill, deprecation_warning: nil)
        expect(result).not_to include('**Deprecated:**')
      end
    end

    context 'with empty or edge-case content' do
      it 'handles empty content string' do
        empty_resolved = build_resolved(name: 'empty', pack: 'test', content: '')
        result = formatter.format_usage(empty_resolved, kind: :skill)
        expect(result).to include('# Applying skill: empty')
        expect(result).to include('---')
      end

      it 'sanitizes markdown in name and pack' do
        pipe_resolved = build_resolved(name: 'bad|name', pack: 'evil|pack', content: 'content')
        result = formatter.format_usage(pipe_resolved, kind: :skill)
        expect(result).to include('bad\|name')
        expect(result).to include('evil\|pack')
      end

      it 'strips newlines from name and pack in the header' do
        newline_resolved = build_resolved(name: "bad\nname", pack: "evil\npack", content: 'content')
        result = formatter.format_usage(newline_resolved, kind: :skill)
        header_line = result.lines.first
        expect(header_line).not_to include("\nname")
        expect(header_line).not_to include("\npack")
      end
    end
  end

  describe 'message constants' do
    it 'provides a no-registry message with path placeholder' do
      message = format(RailsAiBridge::Tools::UsageFormatter::NO_REGISTRY_MESSAGE, path: '/some/path.json')
      expect(message).to include('/some/path.json')
      expect(message).to include('registry manifest')
    end

    it 'provides a not-found skill message with name placeholder' do
      message = format(RailsAiBridge::Tools::UsageFormatter::NOT_FOUND_SKILL_MESSAGE, name: 'missing-skill')
      expect(message).to include('missing-skill')
      expect(message).to include('rails_list_registry')
    end

    it 'provides a not-found agent message with name placeholder' do
      message = format(RailsAiBridge::Tools::UsageFormatter::NOT_FOUND_AGENT_MESSAGE, name: 'missing-agent')
      expect(message).to include('missing-agent')
      expect(message).to include('rails_list_registry')
    end
  end

  describe 'USAGE_VERBS' do
    it 'maps :skill to "Applying skill"' do
      expect(RailsAiBridge::Tools::UsageFormatter::USAGE_VERBS[:skill]).to eq('Applying skill')
    end

    it 'maps :agent to "Activating agent"' do
      expect(RailsAiBridge::Tools::UsageFormatter::USAGE_VERBS[:agent]).to eq('Activating agent')
    end
  end

  describe 'USAGE_FOOTERS' do
    it 'provides a skill footer with work-through instruction' do
      expect(RailsAiBridge::Tools::UsageFormatter::USAGE_FOOTERS[:skill]).to include('Work through every step')
    end

    it 'provides an agent footer with hard-gates instruction' do
      expect(RailsAiBridge::Tools::UsageFormatter::USAGE_FOOTERS[:agent]).to include('hard gates')
    end
  end
end
