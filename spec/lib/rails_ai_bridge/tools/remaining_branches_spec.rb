# frozen_string_literal: true

require 'spec_helper'
require 'generators/rails_ai_bridge/install/profile_resolver'

# Branch-coverage specs for remaining tool, serializer, and generator branches.
RSpec.describe 'Remaining branch coverage' do
  # ------------------------------------------------------------------
  # GetRoutes — pagination, unknown detail, API namespaces in full
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetRoutes do
    before { described_class.reset_cache! }

    context 'with pagination' do
      let(:routes_data) do
        {
          total_routes: 6,
          api_namespaces: [],
          by_controller: {
            'users' => Array.new(3) { |i| { verb: 'GET', path: "/users/#{i}", action: 'show', name: "user_#{i}" } },
            'posts' => Array.new(3) { |i| { verb: 'GET', path: "/posts/#{i}", action: 'show', name: "post_#{i}" } }
          }
        }
      end

      before { allow(described_class).to receive(:cached_section).with(:routes).and_return(routes_data) }

      it 'paginates standard detail with offset and limit' do
        text = described_class.call(detail: 'standard', limit: 2, offset: 2).content.first[:text]
        expect(text).to include('offset:4')
      end

      it 'shows hint when more routes exist in standard' do
        text = described_class.call(detail: 'standard', limit: 2).content.first[:text]
        expect(text).to include('Use `detail:"summary"`')
      end

      it 'paginates full detail with offset and limit' do
        text = described_class.call(detail: 'full', limit: 2, offset: 2).content.first[:text]
        expect(text).to include('offset:4')
      end
    end

    context 'with unknown detail level' do
      let(:routes_data) { { total_routes: 1, by_controller: { 'x' => [{ verb: 'GET', path: '/x', action: 'show' }] } } }

      before { allow(described_class).to receive(:cached_section).with(:routes).and_return(routes_data) }

      it 'returns an error message' do
        text = described_class.call(detail: 'bogus').content.first[:text]
        expect(text).to include('Unknown detail level: bogus')
      end
    end

    context 'with API namespaces in full detail' do
      let(:routes_data) do
        { total_routes: 1, api_namespaces: ['api/v1'], by_controller: { 'x' => [{ verb: 'GET', path: '/x', action: 'show' }] } }
      end

      before { allow(described_class).to receive(:cached_section).with(:routes).and_return(routes_data) }

      it 'includes API namespaces in full output' do
        text = described_class.call(detail: 'full').content.first[:text]
        expect(text).to include('## API namespaces: api/v1')
      end
    end

    context 'with routes having no by_controller key' do
      let(:routes_data) { { total_routes: 0 } }

      before { allow(described_class).to receive(:cached_section).with(:routes).and_return(routes_data) }

      it 'returns empty routes without error' do
        text = described_class.call.content.first[:text]
        expect(text).to include('# Routes (0 total)')
      end
    end
  end

  # ------------------------------------------------------------------
  # GetConfig — all fields
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetConfig do
    before { described_class.reset_cache! }

    it 'renders config with middleware, initializers, and current_attributes' do
      allow(described_class).to receive(:cached_section).with(:config).and_return({
                                                                                    cache_store: ':redis_cache',
                                                                                    session_store: ':cookie_store',
                                                                                    timezone: 'UTC',
                                                                                    middleware_stack: %w[Rack::Cors Rack::Attack],
                                                                                    initializers: %w[devise.rb sidekiq.rb],
                                                                                    current_attributes: ['Current.user']
                                                                                  })
      text = described_class.call.content.first[:text]
      expect(text).to include('## Middleware Stack')
      expect(text).to include('Rack::Cors')
      expect(text).to include('## Initializers')
      expect(text).to include('`devise.rb`')
      expect(text).to include('## CurrentAttributes')
      expect(text).to include('`Current.user`')
    end

    it 'renders config with only cache store' do
      allow(described_class).to receive(:cached_section).with(:config).and_return({ cache_store: ':memory' })
      text = described_class.call.content.first[:text]
      expect(text).to include('Cache store:')
      expect(text).not_to include('Middleware')
    end
  end

  # ------------------------------------------------------------------
  # ExplainSymbol::CliExplorer — error cases
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::ExplainSymbol::CliExplorer do
    it 'raises ExploreError when codegraph CLI is not found' do
      explorer = described_class.new(root: '/tmp')
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
      expect { explorer.explore('User') }.to raise_error(RailsAiBridge::Tools::ExplainSymbol::ExploreError, /not found on PATH/)
    end

    it 'raises ExploreError on timeout' do
      explorer = described_class.new(root: '/tmp', timeout: 0.01)
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)
      expect { explorer.explore('User') }.to raise_error(RailsAiBridge::Tools::ExplainSymbol::ExploreError, /timed out/)
    end

    it 'raises ExploreError with stderr on non-zero exit' do
      explorer = described_class.new(root: '/tmp')
      status = double('status', success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return(['', 'index corrupt', status])
      expect { explorer.explore('User') }.to raise_error(RailsAiBridge::Tools::ExplainSymbol::ExploreError, /index corrupt/)
    end

    it 'raises ExploreError with exit status when stderr is empty' do
      explorer = described_class.new(root: '/tmp')
      status = double('status', success?: false, exitstatus: 42)
      allow(Open3).to receive(:capture3).and_return(['', '', status])
      expect { explorer.explore('User') }.to raise_error(RailsAiBridge::Tools::ExplainSymbol::ExploreError, /exit 42/)
    end

    it 'returns stdout on success' do
      explorer = described_class.new(root: '/tmp')
      status = double('status', success?: true)
      allow(Open3).to receive(:capture3).and_return(['# User markdown', '', status])
      expect(explorer.explore('User')).to eq('# User markdown')
    end
  end

  # ------------------------------------------------------------------
  # ResolveSkill — pack mismatch, agent type
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::ResolveSkill do
    def build_resolved(name:, pack:, path:, content:)
      RailsAiBridge::Registry::ResolvedSkill.new(name: name, pack: pack, path: path, content: content)
    end

    def build_resolver(**stubs)
      defaults = { resolve_skill: nil, resolve_agent: nil, list_skills: [], list_agents: [], active_packs: [] }
      instance_double(RailsAiBridge::Registry::Resolver, **defaults, **stubs)
    end

    context 'when resolving an agent' do
      let(:resolver) { build_resolver }
      let(:agent) { build_resolved(name: 'tdd-workflow', pack: 'rails', path: '/cache/tdd.md', content: '# TDD Workflow') }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_agent).with('tdd-workflow').and_return(agent)
      end

      it 'returns the agent content' do
        text = described_class.call(name: 'tdd-workflow', type: 'agent').content.first[:text]
        expect(text).to include('# tdd-workflow')
        expect(text).to include('# TDD Workflow')
      end
    end

    context 'when agent is not found' do
      let(:resolver) { build_resolver }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        allow(resolver).to receive(:resolve_agent).with('missing').and_return(nil)
      end

      it 'returns agent not found message' do
        text = described_class.call(name: 'missing', type: 'agent').content.first[:text]
        expect(text).to include('Agent `missing` not found')
        expect(text).to include('rails_list_registry')
      end
    end

    context 'when pack-pinned resolution finds skill in different pack' do
      let(:skill) { build_resolved(name: 'code-review', pack: 'core', path: '/cache/code-review.md', content: '# Code Review') }
      let(:pack) { RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: nil, base_path: '/tmp', priority: 1) }
      let(:resolver) { build_resolver(active_packs: [pack], list_skills: [skill], resolve_skill: skill) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        single_resolver = instance_double(RailsAiBridge::Registry::Resolver, resolve_skill: nil)
        allow(RailsAiBridge::Registry::Resolver).to receive(:new).with([pack]).and_return(single_resolver)
      end

      it 'includes pack mismatch warning when requested pack differs' do
        text = described_class.call(name: 'code-review', pack: 'rails').content.first[:text]
        expect(text).to include('Skill `code-review` was found in pack `core`, not `rails`')
      end
    end

    context 'when pack-pinned resolution falls back to priority-based' do
      let(:skill) { build_resolved(name: 'code-review', pack: 'core', path: '/cache/code-review.md', content: '# Code Review') }
      let(:pack) { RailsAiBridge::Registry::LoadedPack.new(name: 'other', tile: nil, base_path: '/tmp', priority: 1) }
      let(:resolver) { build_resolver(active_packs: [pack], list_skills: [skill]) }

      before do
        allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
        single_resolver = instance_double(RailsAiBridge::Registry::Resolver, resolve_skill: nil)
        allow(RailsAiBridge::Registry::Resolver).to receive(:new).with([pack]).and_return(single_resolver)
        allow(resolver).to receive(:resolve_skill).with('code-review').and_return(skill)
      end

      it 'falls back to priority-based resolution' do
        text = described_class.call(name: 'code-review', pack: 'other').content.first[:text]
        expect(text).to include('# code-review')
        expect(text).to include('# Code Review')
      end
    end
  end

  # ------------------------------------------------------------------
  # ProfileResolver — remaining branches
  # ------------------------------------------------------------------
  describe RailsAiBridge::Generators::ProfileResolver do
    let(:shell) { double('shell', say: nil, ask: 'custom') }

    context 'interactive mode with unknown answer' do
      before { allow(shell).to receive(:say) }

      it 'falls back to custom with yellow warning' do
        allow(shell).to receive(:ask).and_return('bogus')
        expect(described_class.new(nil, shell: shell).call).to eq('custom')
        expect(shell).to have_received(:say).with(a_string_including("Unknown profile 'bogus'"), :yellow)
      end
    end

    describe '.formats_for' do
      it 'returns nil for unknown profile' do
        expect(described_class.formats_for('bogus')).to be_nil
      end

      it 'returns nil for custom (interactive)' do
        expect(described_class.formats_for('custom')).to be_nil
      end

      it 'returns all formats for full' do
        formats = described_class.formats_for('full')
        expect(formats).to include(:claude, :json)
      end
    end

    describe '.split_rules_for' do
      it 'returns nil for unknown profile' do
        expect(described_class.split_rules_for('bogus')).to be_nil
      end

      it 'returns false for mcp' do
        expect(described_class.split_rules_for('mcp')).to be false
      end
    end

    describe '.description_for' do
      it 'returns nil for unknown profile' do
        expect(described_class.description_for('bogus')).to be_nil
      end
    end
  end

  # ------------------------------------------------------------------
  # SharedAssistantGuidance — remaining branches
  # ------------------------------------------------------------------
  describe RailsAiBridge::Serializers::SharedAssistantGuidance do
    context 'when anti_hallucination_rules is disabled' do
      around do |example|
        original = RailsAiBridge.configuration.anti_hallucination_rules
        RailsAiBridge.configuration.anti_hallucination_rules = false
        example.run
      ensure
        RailsAiBridge.configuration.anti_hallucination_rules = original
      end

      it 'returns empty array for anti_hallucination_rules_lines' do
        expect(described_class.anti_hallucination_rules_lines).to eq([])
      end

      it 'does not include anti-hallucination heading in compact_engineering_rules_lines' do
        lines = described_class.compact_engineering_rules_lines
        expect(lines).not_to include('## Anti-hallucination')
      end
    end

    describe '.cursor_engineering_mdc_body_lines' do
      it 'includes overrides pointer when show_overrides_pointer is true' do
        lines = described_class.cursor_engineering_mdc_body_lines(show_overrides_pointer: true)
        expect(lines).to include('Repo-specific performance/security: `config/rails_ai_bridge/overrides.md`.')
      end

      it 'omits overrides pointer when show_overrides_pointer is false' do
        lines = described_class.cursor_engineering_mdc_body_lines(show_overrides_pointer: false)
        expect(lines).not_to include('Repo-specific performance/security')
      end
    end

    describe '.claude_full_footer_lines' do
      it 'includes architecture summary when conventions present' do
        lines = described_class.claude_full_footer_lines({ conventions: { architecture: %w[hotwire api] } })
        expect(lines).to include('- Match the project\'s architecture style (hotwire, api)')
      end

      it 'omits architecture summary when conventions absent' do
        lines = described_class.claude_full_footer_lines({})
        expect(lines).not_to include('architecture style')
      end
    end

    describe '.compact_engineering_rules_footer_lines' do
      it 'includes architecture summary when conventions present' do
        lines = described_class.compact_engineering_rules_footer_lines({ conventions: { architecture: ['rails'] } })
        expect(lines.join("\n")).to include('**Match Architecture:**')
        expect(lines.join("\n")).to include('rails')
      end

      it 'omits anti-hallucination when include_anti_hallucination is false' do
        lines = described_class.compact_engineering_rules_footer_lines({}, include_anti_hallucination: false)
        expect(lines).not_to include('## Anti-hallucination')
      end
    end

    describe '.read_assistant_overrides' do
      it 'returns nil when Rails application is not available' do
        allow(described_class).to receive(:resolved_assistant_overrides_path).and_return(nil)
        expect(described_class.read_assistant_overrides).to be_nil
      end

      it 'returns nil when file does not exist' do
        allow(described_class).to receive(:resolved_assistant_overrides_path).and_return('/nonexistent/path.md')
        expect(described_class.read_assistant_overrides).to be_nil
      end

      it 'returns nil when file is empty' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'overrides.md')
          File.write(path, '')
          allow(described_class).to receive(:resolved_assistant_overrides_path).and_return(path)
          expect(described_class.read_assistant_overrides).to be_nil
        end
      end

      it 'returns nil when file has omit-merge marker' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'overrides.md')
          File.write(path, "<!-- rails-ai-bridge:omit-merge -->\n\nSome content")
          allow(described_class).to receive(:resolved_assistant_overrides_path).and_return(path)
          expect(described_class.read_assistant_overrides).to be_nil
        end
      end

      it 'returns content when file is valid' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'overrides.md')
          File.write(path, "## Custom rules\n\n- Do things right")
          allow(described_class).to receive(:resolved_assistant_overrides_path).and_return(path)
          expect(described_class.read_assistant_overrides).to include('Custom rules')
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Provider serializers — error/nil cases
  # ------------------------------------------------------------------
  describe RailsAiBridge::Serializers::Providers::ClaudeRulesSerializer do
    let(:base_context) do
      { app_name: 'Test', rails_version: '7.1', ruby_version: '3.2', environment: 'test',
        models: { 'User' => { table_name: 'users', associations: [], validations: [] } },
        schema: { adapter: 'pg', tables: { 'users' => { columns: [{ name: 'id' }] } } },
        routes: { total_routes: 1, by_controller: { 'users' => [{ verb: 'GET', path: '/users', action: 'index' }] } } }
    end

    it 'skips context reference when models has error' do
      context = base_context.merge(models: { error: 'failed' })
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        context_file = File.join(dir, '.claude', 'rules', 'rails-context.md')
        expect(File.exist?(context_file)).to be false
      end
    end

    it 'handles nil models in context reference' do
      context = base_context.merge(models: nil)
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        context_file = File.join(dir, '.claude', 'rules', 'rails-context.md')
        expect(File.exist?(context_file)).to be true
        body = File.read(context_file)
        expect(body).to include('Rails semantic context')
      end
    end

    it 'skips schema reference when schema has error' do
      context = base_context.merge(schema: { error: 'failed' })
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        schema_file = File.join(dir, '.claude', 'rules', 'rails-schema.md')
        expect(File.exist?(schema_file)).to be false
      end
    end

    it 'skips schema reference when schema is nil' do
      context = base_context.merge(schema: nil)
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        schema_file = File.join(dir, '.claude', 'rules', 'rails-schema.md')
        expect(File.exist?(schema_file)).to be false
      end
    end

    it 'skips models reference when models has error' do
      context = base_context.merge(models: { error: 'failed' })
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        models_file = File.join(dir, '.claude', 'rules', 'rails-models.md')
        expect(File.exist?(models_file)).to be false
      end
    end

    it 'renders schema with nil columns gracefully' do
      context = base_context.merge(schema: { adapter: 'pg', tables: { 'users' => { columns: nil } } })
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-schema.md'))
        expect(body).to include('users (0 cols')
      end
    end

    it 'renders schema with default primary key when missing' do
      context = base_context.merge(schema: { adapter: 'pg', tables: { 'users' => { columns: [{ name: 'id' }] } } })
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-schema.md'))
        expect(body).to include('pk: id')
      end
    end

    it 'renders context without app metadata when missing' do
      context = base_context.merge(app_name: nil, rails_version: nil, ruby_version: nil, environment: nil)
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-context.md'))
        expect(body).not_to include('**Name:**')
        expect(body).not_to include('**Rails:**')
      end
    end
  end

  describe RailsAiBridge::Serializers::Providers::CopilotInstructionsSerializer do
    let(:context) do
      { models: { 'User' => { table_name: 'users', associations: [], validations: [] } },
        controllers: { controllers: { 'UsersController' => { actions: ['index'] } } } }
    end

    it 'skips models instructions when models has error' do
      ctx = context.merge(models: { error: 'failed' })
      Dir.mktmpdir do |dir|
        described_class.new(ctx).call(dir)
        models_file = File.join(dir, '.github', 'instructions', 'rails-models.instructions.md')
        expect(File.exist?(models_file)).to be false
      end
    end

    it 'skips models instructions when models is empty' do
      ctx = context.merge(models: {})
      Dir.mktmpdir do |dir|
        described_class.new(ctx).call(dir)
        models_file = File.join(dir, '.github', 'instructions', 'rails-models.instructions.md')
        expect(File.exist?(models_file)).to be false
      end
    end

    it 'skips controllers instructions when controllers has error' do
      ctx = context.merge(controllers: { error: 'failed' })
      Dir.mktmpdir do |dir|
        described_class.new(ctx).call(dir)
        controllers_file = File.join(dir, '.github', 'instructions', 'rails-controllers.instructions.md')
        expect(File.exist?(controllers_file)).to be false
      end
    end

    it 'skips controllers instructions when no controllers' do
      ctx = context.merge(controllers: { controllers: {} })
      Dir.mktmpdir do |dir|
        described_class.new(ctx).call(dir)
        controllers_file = File.join(dir, '.github', 'instructions', 'rails-controllers.instructions.md')
        expect(File.exist?(controllers_file)).to be false
      end
    end
  end

  describe RailsAiBridge::Serializers::Providers::DevinRulesSerializer do
    let(:context) do
      { app_name: 'Test', models: { 'User' => { table_name: 'users' } },
        schema: { adapter: 'pg', tables: { 'users' => { columns: [{ name: 'id' }] } } } }
    end

    it 'skips unchanged files on second call' do
      Dir.mktmpdir do |dir|
        first = described_class.new(context).call(dir)
        expect(first[:written]).not_to be_empty
        second = described_class.new(context).call(dir)
        expect(second[:written]).to eq([])
        expect(second[:skipped]).not_to be_empty
      end
    end
  end

  describe RailsAiBridge::Serializers::Providers::CursorRulesSerializer do
    let(:context) do
      { app_name: 'Test', models: { 'User' => { table_name: 'users' } },
        schema: { adapter: 'pg', tables: { 'users' => { columns: [{ name: 'id' }] } } },
        controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
        routes: { total_routes: 1, by_controller: { 'users' => [{ verb: 'GET', path: '/users', action: 'index' }] } } }
    end

    it 'skips unchanged files on second call' do
      Dir.mktmpdir do |dir|
        first = described_class.new(context).call(dir)
        expect(first[:written]).not_to be_empty
        second = described_class.new(context).call(dir)
        expect(second[:written]).to eq([])
        expect(second[:skipped]).not_to be_empty
      end
    end
  end

  # ------------------------------------------------------------------
  # GeminiSerializer — full mode
  # ------------------------------------------------------------------
  describe RailsAiBridge::Serializers::Providers::GeminiSerializer do
    let(:context) do
      { app_name: 'Test', rails_version: '7.1', ruby_version: '3.2', generated_at: '2024-01-01',
        models: { 'User' => { table_name: 'users', associations: [], validations: [] } },
        schema: { adapter: 'pg', tables: { 'users' => { columns: [{ name: 'id' }] } } } }
    end

    around do |example|
      original = RailsAiBridge.configuration.context_mode
      RailsAiBridge.configuration.context_mode = :full
      example.run
    ensure
      RailsAiBridge.configuration.context_mode = original
    end

    it 'delegates to MarkdownSerializer in full mode' do
      result = described_class.new(context).call
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  # ------------------------------------------------------------------
  # Factory — NullStrategy and NullSplitRulesStrategy
  # ------------------------------------------------------------------
  describe RailsAiBridge::Serializers::Providers::Factory do
    it 'returns NullStrategy for unknown format' do
      serializer = described_class.for(:unknown_format, { app_name: 'Test' })
      expect(serializer).to be_a(RailsAiBridge::Serializers::Providers::Factory::NullStrategy)
      expect(serializer.call).to be_a(String)
    end

    it 'returns NullSplitRulesStrategy for unknown format' do
      serializer = described_class.split_rules_for(:unknown_format, { app_name: 'Test' })
      expect(serializer).to be_a(RailsAiBridge::Serializers::Providers::Factory::NullSplitRulesStrategy)
      Dir.mktmpdir do |dir|
        result = serializer.call(dir)
        expect(result).to eq({ written: [], skipped: [] })
      end
    end
  end
end
