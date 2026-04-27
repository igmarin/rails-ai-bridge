# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/shared_assistant_guidance'

RSpec.describe RailsAiBridge::Serializers::Providers::RulesOrchestrator do
  subject(:orchestrator) { described_class.new(context: context, config: config) }

  let(:context) do
    {
      app_overview: true,
      app_name: 'MyApp',
      rails_version: '7.1.3',
      ruby_version: '3.3.0',
      environment: 'development',
      database_adapter: 'postgresql',
      gems: {
        notable_gems: [
          { name: 'devise', version: '4.9.0', category: 'auth', note: 'Authentication solution' },
          { name: 'pundit', version: '2.3.0', category: 'auth', note: 'Authorization library' },
          { name: 'rubocop', version: '1.0', category: 'tooling', note: 'Code style linter' }
        ]
      },
      conventions: { architecture: %w[hotwire service_objects rest_api] },
      tests: { framework: 'rspec' },
      config: { cache_store: ':memory_store' },
      models: {
        'User' => { associations: [{ type: 'has_many', name: 'posts' }], validations: [] },
        'Post' => { associations: [], validations: [{ kind: 'presence', attributes: ['title'] }] },
        'Comment' => { associations: [{ type: 'belongs_to', name: 'post' }], validations: [] },
        'Profile' => { associations: [], validations: [] }
      }
    }
  end
  let(:config) { RailsAiBridge::Configuration.new }

  before do
    allow(RailsAiBridge::Serializers::SharedAssistantGuidance).to receive_messages(
      compact_engineering_rules_lines: ['Engine rules'],
      repo_specific_guidance_section_lines: ['Repo guidance'],
      compact_engineering_rules_footer_lines: ['Footer']
    )
    # Stub the McpToolReferenceFormatter to avoid its internal syntax errors from affecting this test
    formatter_instance = double('McpToolReferenceFormatter', call: 'MCP Tool Reference Content')
    allow(RailsAiBridge::Serializers::Providers::McpToolReferenceFormatter).to receive(:new).and_return(formatter_instance)
  end

  describe '.initialize' do
    it 'sets context and config' do
      expect(orchestrator.instance_variable_get(:@context)).to eq(context)
      expect(orchestrator.instance_variable_get(:@config)).to be_a(RailsAiBridge::Configuration)
    end

    it 'uses default config when none provided' do
      default_orchestrator = described_class.new(context: context)
      expect(default_orchestrator.instance_variable_get(:@config)).to eq(RailsAiBridge.configuration)
    end
  end

  describe '#call' do
    it 'returns a markdown string' do
      expect(orchestrator.call).to be_a(String)
    end

    it 'includes the app name and version in the header' do
      expect(orchestrator.call).to include('# MyApp — Project Rules')
      expect(orchestrator.call).to include('Rails 7.1.3 | Ruby 3.3.0')
    end

    it 'includes shared engineering rules' do
      expect(orchestrator.call).to include('Engine rules')
    end

    it 'includes repo-specific guidance' do
      expect(orchestrator.call).to include('Repo guidance')
    end

    it 'includes the application stack and overview' do
      output = orchestrator.call
      expect(output).to include('## Application Stack & Overview')
      expect(output).to include('- **Name:** `MyApp`')
      expect(output).to include('- **Database:** `postgresql`')
    end

    it 'includes notable gems sorted by category and name' do
      output = orchestrator.call
      lines = output.split("\n")

      # Should be ordered: devise (auth), pundit (auth), rubocop (tooling)
      devise_index = lines.index { |l| l.include?('`devise`') }
      pundit_index = lines.index { |l| l.include?('`pundit`') }
      rubocop_index = lines.index { |l| l.include?('`rubocop`') }

      expect(devise_index).to be < pundit_index
      expect(pundit_index).to be < rubocop_index
    end

    it 'includes architecture and conventions' do
      output = orchestrator.call
      expect(output).to include('## Architecture & Conventions')
      expect(output).to include('- Hotwire')
      expect(output).to include('- Service objects')
      expect(output).to include('- Rest api')
    end

    it 'includes key development considerations' do
      output = orchestrator.call
      expect(output).to include('## Key Development Considerations')
      expect(output).to include('- **Test Framework:** `rspec`')
      expect(output).to include('- **Cache Store:** `:memory_store`')
    end

    it 'includes the MCP Tool Reference' do
      expect(orchestrator.call).to include('MCP Tool Reference Content')
    end

    it 'includes the shared footer' do
      expect(orchestrator.call).to include('Footer')
    end

    it 'uses literal newline characters for formatting' do
      expect(orchestrator.call).to include("\n")
    end

    context 'when models are present' do
      it 'appends a compact models section with limit' do
        allow(config).to receive(:copilot_compact_model_list_limit).and_return(2)
        output = orchestrator.call
        expect(output).to include('## Models (4 total)')
        expect(output).to include('- Comment (1 associations)')
        expect(output).to include('- Post (0 associations)')
        expect(output).to include('...2 more — `rails_get_model_details(detail:"summary")`.')
        expect(output).not_to include('- User')
        expect(output).not_to include('- Profile')
      end

      it 'handles zero model limit' do
        allow(config).to receive(:copilot_compact_model_list_limit).and_return(0)
        output = orchestrator.call
        expect(output).to include('## Models (4 total)')
        expect(output).to include('- _Use `rails_get_model_details(detail:"summary")` for names._')
        expect(output).not_to include('- User')
      end

      it 'handles models with no associations' do
        context_with_no_assocs = context.merge(
          models: { 'SimpleModel' => { associations: [] } }
        )
        no_assocs_orchestrator = described_class.new(context: context_with_no_assocs, config: config)
        output = no_assocs_orchestrator.call
        expect(output).to include('## Models (1 total)')
        expect(output).to include('- SimpleModel (0 associations)')
      end

      it 'handles models with nil associations' do
        context_with_nil_assocs = context.merge(
          models: { 'SimpleModel' => { associations: nil } }
        )
        nil_assocs_orchestrator = described_class.new(context: context_with_nil_assocs, config: config)
        output = nil_assocs_orchestrator.call
        expect(output).to include('## Models (1 total)')
        expect(output).to include('- SimpleModel (0 associations)')
      end
    end

    context 'when models are not present or errored' do
      let(:context) { { app_name: 'MyApp', models: { error: 'Models error' } } }

      it 'does not append a models section' do
        expect(orchestrator.call).not_to include('## Models')
      end
    end

    context 'with minimal context data' do
      let(:minimal_context) { { app_name: 'MinimalApp' } }
      let(:minimal_orchestrator) { described_class.new(context: minimal_context, config: config) }

      it 'generates document with available data only' do
        result = minimal_orchestrator.call

        expect(result).to include('# MinimalApp — Project Rules')
        expect(result).to include('Engine rules')
        expect(result).to include('Repo guidance')
        expect(result).to include('Footer')
        expect(result).not_to include('## Notable Gems')
        expect(result).not_to include('## Architecture & Conventions')
        expect(result).to include('## Application Stack & Overview')
        expect(result).to include('- **Name:** `MinimalApp`')
      end
    end
  end
end
