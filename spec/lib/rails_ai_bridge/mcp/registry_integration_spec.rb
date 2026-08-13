# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/registry/tile_manifest'

RSpec.describe 'Registry tools integration in MCP server' do
  let(:app) { Rails.application }
  let(:server) { RailsAiBridge::Server.new(app).build }

  let(:registry_tool_names) do
    %w[rails_list_registry rails_resolve_skill rails_use_skill rails_use_agent]
  end

  around do |example|
    original_ttl = RailsAiBridge.configuration.mcp.tool_result_cache_ttl
    RailsAiBridge::ToolResultCache.reset!
    # Caching is enabled so the full wrapper chain
    # (InstrumentedTool -> CachedTool -> raw tool) is exercised and the
    # CachedTool translates server_context to _server_context.
    RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
    example.run
  ensure
    RailsAiBridge.configuration.mcp.tool_result_cache_ttl = original_ttl
    RailsAiBridge::ToolResultCache.reset!
  end

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

  def build_resolved(name:, pack:, path:, content:)
    RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: path, content: content)
  end

  def build_resolver(**stubs)
    defaults = { resolve_skill: nil, resolve_agent: nil, check_deprecated: nil,
                 list_skills: [], list_agents: [], active_packs: [] }
    instance_double(RailsAiBridge::Registry::Resolver, **defaults, **stubs)
  end

  def tool_response(tool_name, **arguments)
    server.tools[tool_name].call(**arguments)
  end

  def response_text(tool_name, **arguments)
    tool_response(tool_name, **arguments).content.first[:text]
  end

  describe 'tool registration' do
    it 'registers all four registry tools in the MCP server' do
      registry_tool_names.each do |name|
        expect(server.tools).to have_key(name)
      end
    end

    it 'wraps registry tools with Instrumentation::InstrumentedTool' do
      registry_tool_names.each do |name|
        expect(server.tools[name]).to be_a(RailsAiBridge::Instrumentation::InstrumentedTool)
      end
    end
  end

  describe 'rails_list_registry' do
    context 'when no registry manifest is configured' do
      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

      it 'returns a setup message mentioning the registry manifest' do
        text = response_text('rails_list_registry', type: 'skills')

        expect(text).to include('registry manifest')
        expect(text).to include('config/rails_ai_bridge/registry.json')
      end
    end

    context 'when skills are available' do
      let(:skills) do
        [
          RailsAiBridge::Registry::SkillSummary.new(name: 'code-review', pack: 'rails', description: 'Review Rails code.'),
          RailsAiBridge::Registry::SkillSummary.new(name: 'write-tests', pack: 'core', description: 'Write RSpec tests.')
        ]
      end
      let(:resolver) { build_resolver(list_skills: skills) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'lists all skills with name, pack, and description' do
        text = response_text('rails_list_registry', type: 'skills')

        expect(text).to include('# Available Skills')
        expect(text).to include('code-review')
        expect(text).to include('rails')
        expect(text).to include('write-tests')
        expect(text).to include('core')
      end

      it 'filters skills by pack' do
        text = response_text('rails_list_registry', type: 'skills', pack: 'rails')

        expect(text).to include('code-review')
        expect(text).not_to include('write-tests')
      end
    end

    context 'when agents are available' do
      let(:agents) do
        [
          RailsAiBridge::Registry::SkillSummary.new(name: 'tdd-workflow', pack: 'rails', description: 'Full TDD cycle.')
        ]
      end
      let(:resolver) { build_resolver(list_agents: agents) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'lists all agents' do
        text = response_text('rails_list_registry', type: 'agents')

        expect(text).to include('# Available Agents')
        expect(text).to include('tdd-workflow')
      end
    end

    context 'when packs are loaded' do
      let(:active_packs) do
        [
          RailsAiBridge::Registry::LoadedPack.new(
            name: 'rails',
            tile: build_tile(name: 'rails', version: '1.2.0', summary: 'Rails-specific skills.'),
            base_path: '/tmp/rails',
            priority: 10
          )
        ]
      end
      let(:resolver) { build_resolver(active_packs: active_packs) }

      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver) }

      it 'lists active packs with version and priority' do
        text = response_text('rails_list_registry', type: 'packs')

        expect(text).to include('# Active Skill Packs')
        expect(text).to include('rails')
        expect(text).to include('1.2.0')
        expect(text).to include('10')
      end
    end
  end

  describe 'rails_resolve_skill' do
    context 'when no registry manifest is configured' do
      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

      it 'returns a setup message mentioning the registry manifest' do
        text = response_text('rails_resolve_skill', name: 'code-review')

        expect(text).to include('registry manifest')
      end
    end

    context 'when the skill is found' do
      let(:skill) do
        build_resolved(name: 'code-review', pack: 'rails',
                       path: '/cache/rails/code-review/SKILL.md',
                       content: "# Code Review\n\nReview Rails PRs.")
      end
      let(:resolver) { build_resolver(resolve_skill: skill) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
      end

      it 'returns the full skill content with name and pack' do
        text = response_text('rails_resolve_skill', name: 'code-review')

        expect(text).to include('# code-review')
        expect(text).to include('rails')
        expect(text).to include(skill.content)
      end
    end

    context 'when the skill is not found' do
      let(:resolver) { build_resolver(resolve_skill: nil) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_skill).with('nonexistent-skill').and_return(nil)
      end

      it 'mentions the skill name and suggests rails_list_registry' do
        text = response_text('rails_resolve_skill', name: 'nonexistent-skill')

        expect(text).to include('nonexistent-skill')
        expect(text).to include('rails_list_registry')
      end
    end

    context 'when resolving an agent' do
      let(:agent) do
        build_resolved(name: 'tdd-workflow', pack: 'rails',
                       path: '/cache/rails/tdd-workflow/AGENT.md',
                       content: "# TDD Workflow\n\nFull TDD cycle.")
      end
      let(:resolver) { build_resolver(resolve_agent: agent) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_agent).with('tdd-workflow').and_return(agent)
      end

      it 'returns the full agent content' do
        text = response_text('rails_resolve_skill', name: 'tdd-workflow', type: 'agent')

        expect(text).to include('# tdd-workflow')
        expect(text).to include(agent.content)
      end
    end
  end

  describe 'rails_use_skill' do
    context 'when no registry manifest is configured' do
      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

      it 'returns a setup message mentioning the registry manifest' do
        text = response_text('rails_use_skill', name: 'code-review')

        expect(text).to include('registry manifest')
      end
    end

    context 'when the skill is found' do
      let(:skill) do
        build_resolved(name: 'code-review', pack: 'rails',
                       path: '/cache/rails/code-review/SKILL.md',
                       content: "# Code Review\n\nReview Rails PRs.")
      end
      let(:resolver) { build_resolver(resolve_skill: skill, check_deprecated: nil) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
        allow(resolver).to receive(:check_deprecated).with('code-review').and_return(nil)
      end

      it 'frames the output as an application directive with skill content' do
        text = response_text('rails_use_skill', name: 'code-review')

        expect(text).to include('Applying skill: code-review')
        expect(text).to include('rails')
        expect(text).to include(skill.content)
        expect(text).to include('Work through every step')
      end
    end

    context 'when the skill is not found' do
      let(:resolver) { build_resolver(resolve_skill: nil) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_skill).with('nonexistent-skill').and_return(nil)
      end

      it 'mentions the skill name and suggests rails_list_registry' do
        text = response_text('rails_use_skill', name: 'nonexistent-skill')

        expect(text).to include('nonexistent-skill')
        expect(text).to include('rails_list_registry')
      end
    end
  end

  describe 'rails_use_agent' do
    context 'when no registry manifest is configured' do
      before { allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(nil) }

      it 'returns a setup message mentioning the registry manifest' do
        text = response_text('rails_use_agent', name: 'tdd-workflow')

        expect(text).to include('registry manifest')
      end
    end

    context 'when the agent is found' do
      let(:agent) do
        build_resolved(name: 'tdd-workflow', pack: 'core',
                       path: '/cache/core/agents/tdd-workflow.md',
                       content: "# TDD Workflow\n\nRed, green, refactor.")
      end
      let(:resolver) { build_resolver(resolve_agent: agent) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_agent).with('tdd-workflow').and_return(agent)
      end

      it 'frames the output as an activation directive with agent content' do
        text = response_text('rails_use_agent', name: 'tdd-workflow')

        expect(text).to include('Activating agent: tdd-workflow')
        expect(text).to include('core')
        expect(text).to include(agent.content)
        expect(text).to include('end to end')
      end
    end

    context 'when the agent is not found' do
      let(:resolver) { build_resolver(resolve_agent: nil) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_agent).with('nonexistent-agent').and_return(nil)
      end

      it 'mentions the agent name and suggests rails_list_registry with agents type' do
        text = response_text('rails_use_agent', name: 'nonexistent-agent')

        expect(text).to include('nonexistent-agent')
        expect(text).to include('rails_list_registry type=agents')
      end
    end
  end
end
