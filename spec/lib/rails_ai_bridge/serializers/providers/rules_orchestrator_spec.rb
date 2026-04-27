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
        expect(result).not_to include('## Application Stack & Overview')
      end
    end
  end

  describe 'private methods (characterization)' do
    describe '#render_stack_overview' do
      it 'returns formatted stack information' do
        result = orchestrator.send(:render_stack_overview)

        expect(result).to include('## Application Stack & Overview')
        expect(result).to include('- **Name:** `MyApp`')
        expect(result).to include('- **Rails:** `7.1.3`')
        expect(result).to include('- **Ruby:** `3.3.0`')
        expect(result).to include('- **Environment:** `development`')
        expect(result).to include('- **Database:** `postgresql`')
      end

      it 'returns empty array when app_overview is missing' do
        context_without_overview = context.except(:app_overview)
        orchestrator_without_overview = described_class.new(context: context_without_overview, config: config)

        result = orchestrator_without_overview.send(:render_stack_overview)

        expect(result).to eq([])
      end

      it 'handles missing optional fields gracefully' do
        minimal_context = { app_name: 'TestApp', app_overview: {} }
        minimal_orchestrator = described_class.new(context: minimal_context, config: config)

        result = minimal_orchestrator.send(:render_stack_overview)

        expect(result).to include('## Application Stack & Overview')
        expect(result).to include('- **Name:** `TestApp`')
        expect(result).not_to include('- **Rails:**')
        expect(result).not_to include('- **Ruby:**')
      end
    end

    describe '#render_notable_gems' do
      it 'returns formatted gems information' do
        result = orchestrator.send(:render_notable_gems)

        expect(result).to include('## Notable Gems')
        expect(result).to include('- `devise` (`4.9.0`): Authentication solution')
        expect(result).to include('- `pundit` (`2.3.0`): Authorization library')
        expect(result).to include('- `rubocop` (`1.0`): Code style linter')
      end

      it 'returns empty array when no notable gems' do
        context_without_gems = context.except(:gems)
        orchestrator_without_gems = described_class.new(context: context_without_gems, config: config)

        result = orchestrator_without_gems.send(:render_notable_gems)

        expect(result).to eq([])
      end

      it 'returns empty array when notable_gems is empty' do
        context_with_empty_gems = context.merge(gems: { notable_gems: [] })
        orchestrator_with_empty_gems = described_class.new(context: context_with_empty_gems, config: config)

        result = orchestrator_with_empty_gems.send(:render_notable_gems)

        expect(result).to eq([])
      end

      it 'returns empty array when gems is nil' do
        context_with_nil_gems = context.merge(gems: nil)
        orchestrator_with_nil_gems = described_class.new(context: context_with_nil_gems, config: config)

        result = orchestrator_with_nil_gems.send(:render_notable_gems)

        expect(result).to eq([])
      end
    end

    describe '#render_architecture' do
      it 'returns formatted architecture information' do
        result = orchestrator.send(:render_architecture)

        expect(result).to include('## Architecture & Conventions')
        expect(result).to include('- Hotwire')
        expect(result).to include('- Service objects')
        expect(result).to include('- Rest api')
      end

      it 'returns empty array when no conventions' do
        context_without_conventions = context.except(:conventions)
        orchestrator_without_conventions = described_class.new(context: context_without_conventions, config: config)

        result = orchestrator_without_conventions.send(:render_architecture)

        expect(result).to eq([])
      end

      it 'returns empty array when architecture is empty' do
        context_with_empty_arch = context.merge(conventions: { architecture: [] })
        orchestrator_with_empty_arch = described_class.new(context: context_with_empty_arch, config: config)

        result = orchestrator_with_empty_arch.send(:render_architecture)

        expect(result).to eq([])
      end

      it 'returns empty array when conventions is nil' do
        context_with_nil_conventions = context.merge(conventions: nil)
        orchestrator_with_nil_conventions = described_class.new(context: context_with_nil_conventions, config: config)

        result = orchestrator_with_nil_conventions.send(:render_architecture)

        expect(result).to eq([])
      end
    end

    describe '#render_key_considerations' do
      it 'returns formatted considerations information' do
        result = orchestrator.send(:render_key_considerations)

        expect(result).to include('## Key Development Considerations')
        expect(result).to include('- **Test Framework:** `rspec`')
        expect(result).to include('- **Cache Store:** `:memory_store`')
      end

      it 'returns empty array when no tests or config' do
        minimal_context = {}
        minimal_orchestrator = described_class.new(context: minimal_context, config: config)

        result = minimal_orchestrator.send(:render_key_considerations)

        expect(result).to eq([])
      end

      it 'handles missing test framework' do
        context_without_tests = context.except(:tests)
        orchestrator_without_tests = described_class.new(context: context_without_tests, config: config)

        result = orchestrator_without_tests.send(:render_key_considerations)

        expect(result).to include('## Key Development Considerations')
        expect(result).to include('- **Cache Store:** `:memory_store`')
        expect(result).not_to include('- **Test Framework:**')
      end

      it 'handles missing config cache_store' do
        context_without_cache = context.merge(config: {})
        orchestrator_without_cache = described_class.new(context: context_without_cache, config: config)

        result = orchestrator_without_cache.send(:render_key_considerations)

        expect(result).to include('## Key Development Considerations')
        expect(result).to include('- **Test Framework:** `rspec`')
        expect(result).not_to include('- **Cache Store:**')
      end

      it 'handles nil tests and config' do
        context_with_nil = context.merge(tests: nil, config: nil)
        orchestrator_with_nil = described_class.new(context: context_with_nil, config: config)

        result = orchestrator_with_nil.send(:render_key_considerations)

        expect(result).to eq([])
      end
    end

    describe '#append_compact_cursorrules_models_section' do
      it 'appends models section to lines array' do
        lines = []
        orchestrator.send(:append_compact_cursorrules_models_section, lines, context[:models])

        expect(lines).to include('## Models (4 total)')
        expect(lines).to include('- Comment (1 associations)')
        expect(lines).to include('')
      end

      it 'does nothing when models is not a hash' do
        lines = []
        orchestrator.send(:append_compact_cursorrules_models_section, lines, 'invalid')

        expect(lines).to eq([])
      end

      it 'does nothing when models has error' do
        models_with_error = { error: 'Failed to load models' }
        lines = []
        orchestrator.send(:append_compact_cursorrules_models_section, lines, models_with_error)

        expect(lines).to eq([])
      end

      it 'does nothing when models is empty' do
        lines = []
        orchestrator.send(:append_compact_cursorrules_models_section, lines, {})

        expect(lines).to eq([])
      end

      it 'handles negative limit gracefully' do
        allow(config).to receive(:copilot_compact_model_list_limit).and_return(-1)
        lines = []
        orchestrator.send(:append_compact_cursorrules_models_section, lines, context[:models])

        expect(lines).to include('## Models (4 total)')
        expect(lines).to include('- _Use `rails_get_model_details(detail:"summary")` for names._')
      end
    end

    describe '#render_footer' do
      it 'returns shared footer lines' do
        result = orchestrator.send(:render_footer)

        expect(result).to include('Footer')
      end
    end
  end
end
