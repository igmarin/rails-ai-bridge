# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::BaseProviderSerializer do
  subject(:serializer) { described_class.new(base_context, config: config) }

  let(:base_context) do
    {
      app_name: 'TestApp',
      rails_version: '8.0',
      ruby_version: '3.4',
      generated_at: '2026-01-01T00:00:00Z',
      schema: { adapter: 'postgresql', total_tables: 5, tables: {} },
      models: {
        'User' => { associations: [{ type: 'has_many', name: 'posts' }], validations: [{ kind: 'presence', attributes: ['email'] }], table_name: 'users', enums: {} },
        'Post' => { associations: [], validations: [], table_name: 'posts', enums: {} }
      },
      routes: { total_routes: 10, by_controller: {} },
      gems: { notable_gems: [{ name: 'devise', category: :auth }] },
      conventions: { architecture: ['MVC'], patterns: ['Service objects'], config_files: ['config/database.yml'] },
      jobs: { jobs: [{ name: 'WelcomeJob' }], mailers: [], channels: [] },
      auth: { authentication: { devise: ['User'] }, authorization: {} },
      migrations: { total: 20, pending: [] }
    }
  end
  let(:config) { RailsAiBridge::Configuration.new }

  # Isolate global configuration to prevent order-dependent test behavior
  around do |example|
    original = RailsAiBridge.instance_variable_get(:@configuration)
    RailsAiBridge.instance_variable_set(:@configuration, RailsAiBridge::Configuration.new)
    example.run
  ensure
    RailsAiBridge.instance_variable_set(:@configuration, original)
  end

  describe '#initialize' do
    it 'assigns context' do
      expect(serializer.context).to eq(base_context)
    end

    it 'assigns config' do
      expect(serializer.config).to eq(config)
    end

    it 'uses global configuration by default' do
      s = described_class.new(base_context)
      expect(s.config).to eq(RailsAiBridge.configuration)
    end
  end

  describe '#render_compact' do
    it 'returns a String' do
      expect(serializer.render_compact).to be_a(String)
    end

    it 'includes the app name in the header' do
      expect(serializer.render_compact).to include('TestApp')
    end

    it 'includes rails version' do
      expect(serializer.render_compact).to include('Rails 8.0')
    end

    it 'includes ruby version' do
      expect(serializer.render_compact).to include('Ruby 3.4')
    end

    it 'includes generated_at timestamp' do
      expect(serializer.render_compact).to include('2026-01-01T00:00:00Z')
    end

    it 'trims output to claude_max_lines when exceeded' do
      config.claude_max_lines = 5
      lines = serializer.render_compact.split("\n")
      expect(lines.size).to be <= 5
      expect(serializer.render_compact).to include('Context trimmed')
    end

    it 'does not trim when within claude_max_lines' do
      config.claude_max_lines = 1000
      expect(serializer.render_compact).not_to include('Context trimmed')
    end

    it 'includes MCP pointer in trimmed output' do
      config.claude_max_lines = 5
      expect(serializer.render_compact).to include('MCP tools')
    end
  end

  describe '#render_header' do
    it 'returns an Array of Strings' do
      expect(serializer.render_header).to be_an(Array)
      expect(serializer.render_header).to all(be_a(String))
    end

    it 'contains the app name heading' do
      expect(serializer.render_header).to include('# TestApp — AI Context')
    end

    it 'contains the rails-ai-bridge version attribution' do
      expect(serializer.render_header.join).to include('rails-ai-bridge')
    end

    it 'handles missing app_name gracefully (nil becomes part of heading)' do
      ctx = base_context.merge(app_name: nil)
      s = described_class.new(ctx, config: config)
      expect { s.render_header }.not_to raise_error
    end
  end

  describe '#render_stack_overview' do
    it 'returns an Array' do
      expect(serializer.render_stack_overview).to be_an(Array)
    end

    it 'includes database adapter and table count' do
      lines = serializer.render_stack_overview
      expect(lines.join).to include('postgresql')
      expect(lines.join).to include('5 tables')
    end

    it 'includes model count' do
      expect(serializer.render_stack_overview.join).to include('Models: 2')
    end

    it 'includes job count when jobs present' do
      expect(serializer.render_stack_overview.join).to include('1 jobs')
    end

    it 'skips database line when schema has error' do
      ctx = base_context.merge(schema: { error: 'DB unavailable' })
      s = described_class.new(ctx, config: config)
      expect(s.render_stack_overview.join).not_to include('postgresql')
    end

    it 'skips models line when models has error' do
      ctx = base_context.merge(models: { error: 'failed' })
      s = described_class.new(ctx, config: config)
      expect(s.render_stack_overview.join).not_to include('Models:')
    end

    it 'skips auth line when no auth detected' do
      ctx = base_context.merge(auth: { authentication: {}, authorization: {} })
      s = described_class.new(ctx, config: config)
      expect(s.render_stack_overview.join).not_to include('Auth:')
    end

    it 'skips auth line when nested auth sections are malformed' do
      ctx = base_context.merge(auth: { authentication: 'oops', authorization: [:also_bad] })
      s = described_class.new(ctx, config: config)
      expect(s.render_stack_overview.join).not_to include('Auth:')
    end

    it 'includes pending migrations count' do
      ctx = base_context.merge(migrations: { total: 20, pending: %w[m1 m2] })
      s = described_class.new(ctx, config: config)
      expect(s.render_stack_overview.join).to include('2 pending')
    end
  end

  describe '#render_key_models' do
    it 'returns an Array' do
      expect(serializer.render_key_models).to be_an(Array)
    end

    it 'lists User model' do
      expect(serializer.render_key_models.join).to include('User')
    end

    it 'describes key models as relevance ordered' do
      expect(serializer.render_key_models.join("\n")).to include('ordered by relevance')
    end

    it 'returns empty array when models is missing' do
      ctx = base_context.merge(models: nil)
      s = described_class.new(ctx, config: config)
      expect(s.render_key_models).to eq([])
    end

    it 'returns empty array when models has error' do
      ctx = base_context.merge(models: { error: 'oops' })
      s = described_class.new(ctx, config: config)
      expect(s.render_key_models).to eq([])
    end

    it 'caps display at 15 and shows overflow hint' do
      models = 20.times.to_h { |i| ["Model#{i}", { associations: [], validations: [], table_name: "m#{i}", enums: {} }] }
      ctx = base_context.merge(models: models)
      s = described_class.new(ctx, config: config)
      output = s.render_key_models.join("\n")
      expect(output).to include('5 more')
    end

    it 'sorts models by relevance' do
      models = {
        'Simple' => { associations: [], validations: [], table_name: 'simples', enums: {} },
        'Complex' => { associations: 10.times.map { |j| { type: 'has_many', name: "r#{j}" } }, validations: [], table_name: 'complexes', enums: {} }
      }
      ctx = base_context.merge(models: models)
      s = described_class.new(ctx, config: config)
      lines = s.render_key_models.join("\n")
      expect(lines.index('Complex')).to be < lines.index('Simple')
    end

    it 'skips malformed model payloads' do
      models = {
        'Valid' => { associations: [], validations: [], table_name: 'valids', enums: {} },
        'Broken' => 'not a model payload'
      }
      ctx = base_context.merge(models: models)
      s = described_class.new(ctx, config: config)
      output = s.render_key_models.join("\n")

      expect(output).to include('Valid')
      expect(output).not_to include('Broken')
    end
  end

  describe '#render_notable_gems' do
    it 'returns an Array' do
      expect(serializer.render_notable_gems).to be_an(Array)
    end

    it 'includes devise gem' do
      expect(serializer.render_notable_gems.join).to include('devise')
    end

    it 'returns empty array when gems is nil' do
      ctx = base_context.merge(gems: nil)
      s = described_class.new(ctx, config: config)
      expect(s.render_notable_gems).to eq([])
    end

    it 'returns empty array when gems has error' do
      ctx = base_context.merge(gems: { error: 'failed' })
      s = described_class.new(ctx, config: config)
      expect(s.render_notable_gems).to eq([])
    end

    it 'returns empty array when notable gems list is empty' do
      ctx = base_context.merge(gems: { notable_gems: [] })
      s = described_class.new(ctx, config: config)
      expect(s.render_notable_gems).to eq([])
    end

    it 'groups gems by category' do
      gems = {
        notable_gems: [
          { name: 'devise', category: :auth },
          { name: 'pundit', category: :auth },
          { name: 'sidekiq', category: :background }
        ]
      }
      ctx = base_context.merge(gems: gems)
      s = described_class.new(ctx, config: config)
      output = s.render_notable_gems.join("\n")
      expect(output).to include('devise, pundit')
      expect(output).to include('sidekiq')
    end
  end

  describe '#render_architecture' do
    it 'returns an Array' do
      expect(serializer.render_architecture).to be_an(Array)
    end

    it 'includes architecture patterns' do
      expect(serializer.render_architecture.join).to include('MVC')
    end

    it 'returns empty array when conventions missing' do
      ctx = base_context.merge(conventions: nil)
      s = described_class.new(ctx, config: config)
      expect(s.render_architecture).to eq([])
    end

    it 'returns empty array when conventions has error' do
      ctx = base_context.merge(conventions: { error: 'failed' })
      s = described_class.new(ctx, config: config)
      expect(s.render_architecture).to eq([])
    end

    it 'returns empty array when architecture, patterns, and config_files are all empty' do
      ctx = base_context.merge(conventions: { architecture: [], patterns: [], config_files: [] })
      s = described_class.new(ctx, config: config)
      expect(s.render_architecture).to eq([])
    end

    it 'caps patterns at 8' do
      patterns = 15.times.map { |i| "Pattern#{i}" }
      ctx = base_context.merge(conventions: { architecture: [], patterns: patterns, config_files: [] })
      s = described_class.new(ctx, config: config)
      output = s.render_architecture.join("\n")
      expect(output).to match(/\bPattern7\b/)
      expect(output).not_to match(/^-\s+Pattern8$/)
    end
  end

  describe '#render_key_considerations' do
    it 'returns an Array' do
      expect(serializer.render_key_considerations).to be_an(Array)
    end

    it 'mentions Performance' do
      expect(serializer.render_key_considerations.join).to include('Performance')
    end

    it 'mentions Security' do
      expect(serializer.render_key_considerations.join).to include('Security')
    end

    it 'mentions Data Drift' do
      expect(serializer.render_key_considerations.join).to include('Data Drift')
    end

    it 'mentions MCP Exposure' do
      expect(serializer.render_key_considerations.join).to include('MCP Exposure')
    end
  end

  describe '#render_key_config_files' do
    it 'returns an Array' do
      expect(serializer.render_key_config_files).to be_an(Array)
    end

    it 'includes config/database.yml' do
      expect(serializer.render_key_config_files.join).to include('config/database.yml')
    end

    it 'returns empty array when conventions missing' do
      ctx = base_context.merge(conventions: nil)
      s = described_class.new(ctx, config: config)
      expect(s.render_key_config_files).to eq([])
    end

    it 'caps at 5 config files' do
      files = 10.times.map { |i| "config/file#{i}.yml" }
      ctx = base_context.merge(conventions: { architecture: [], patterns: [], config_files: files })
      s = described_class.new(ctx, config: config)
      output = s.render_key_config_files.join("\n")
      expect(output).to include('config/file4.yml')
      expect(output).not_to match(%r{^-\s+`config/file5\.yml`$})
    end
  end

  describe '#render_commands' do
    it 'returns an Array' do
      expect(serializer.render_commands).to be_an(Array)
    end

    it 'includes bin/dev' do
      expect(serializer.render_commands.join).to include('bin/dev')
    end

    it 'includes rubocop' do
      expect(serializer.render_commands.join).to include('rubocop')
    end

    it 'includes db:migrate' do
      expect(serializer.render_commands.join).to include('db:migrate')
    end
  end

  describe '#render_footer' do
    it 'returns an Array' do
      expect(serializer.render_footer).to be_an(Array)
    end
  end

  # Characterization tests for upcoming refactors
  describe 'private method behaviors (characterization)' do
    describe 'max lines enforcement' do
      let(:line_enforcer) { serializer.send(:line_enforcer) }

      it 'trims to claude_max_lines - 2 when exceeded' do
        config.claude_max_lines = 5
        lines = %w[a b c d e f]
        trimmed = line_enforcer.enforce(lines)
        expect(trimmed.size).to eq(5)
        expect(trimmed.last(2)).to eq(['', '_Context trimmed. Use MCP tools for full details._'])
      end

      it 'returns original lines when within limit' do
        config.claude_max_lines = 10
        lines = %w[a b c]
        trimmed = line_enforcer.enforce(lines)
        expect(trimmed).to eq(lines)
      end

      it 'honors a zero line limit' do
        config.claude_max_lines = 0
        expect(line_enforcer.enforce(%w[a b c])).to eq([])
      end

      it 'honors a one line limit' do
        config.claude_max_lines = 1
        expect(line_enforcer.enforce(%w[a b c])).to eq(['_Context trimmed. Use MCP tools for full details._'])
      end
    end

    describe 'notable gems extraction' do
      it 'extracts from :notable_gems key' do
        gems = { notable_gems: [{ name: 'devise' }] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'devise' }])
      end

      it 'falls back to :notable key' do
        gems = { notable: [{ name: 'pundit' }] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'pundit' }])
      end

      it 'falls back to :detected key' do
        gems = { detected: [{ name: 'sidekiq' }] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'sidekiq' }])
      end

      it 'returns empty array when none found' do
        gems = { other: [] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([])
      end

      it 'returns empty array for nil gems' do
        expect(serializer.send(:extract_notable_gems, nil)).to eq([])
      end

      it 'handles empty arrays in keys' do
        gems = { notable_gems: [], notable: [], detected: [] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([])
      end

      it 'wraps a single hash payload' do
        gems = { notable_gems: { name: 'devise' } }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'devise' }])
      end

      it 'filters malformed gem entries' do
        gems = { notable_gems: [{ name: 'devise' }, 'bad', nil] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'devise' }])
      end

      it 'falls back when earlier gem keys are empty' do
        gems = { notable_gems: [], notable: [{ name: 'pundit' }] }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([{ name: 'pundit' }])
      end

      it 'returns empty array for malformed gem payloads' do
        gems = { notable_gems: 'devise' }
        expect(serializer.send(:extract_notable_gems, gems)).to eq([])
      end
    end

    describe 'stack line builders' do
      let(:stack_builder) { serializer.send(:stack_overview_builder) }

      it 'database_stack_line with valid schema' do
        schema = { adapter: 'postgresql', total_tables: 10 }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::DatabaseStackBuilder.build(schema)).to eq('- Database: postgresql — 10 tables')
      end

      it 'database_stack_line with nil schema' do
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::DatabaseStackBuilder.build(nil)).to be_nil
      end

      it 'database_stack_line with error schema' do
        schema = { error: 'failed' }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::DatabaseStackBuilder.build(schema)).to be_nil
      end

      it 'database_stack_line with missing adapter' do
        schema = { total_tables: 10 }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::DatabaseStackBuilder.build(schema)).to eq('- Database:  — 10 tables')
      end

      it 'models_stack_line with valid models' do
        models = { user: {}, post: {} }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::ModelsStackBuilder.build(models)).to eq('- Models: 2')
      end

      it 'models_stack_line with empty models' do
        models = {}
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::ModelsStackBuilder.build(models)).to eq('- Models: 0')
      end

      it 'models_stack_line with nil models' do
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::ModelsStackBuilder.build(nil)).to be_nil
      end

      it 'models_stack_line with more than 5 models' do
        models = { User: {}, Post: {}, Comment: {}, Tag: {}, Category: {}, Author: {} }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::ModelsStackBuilder.build(models)).to eq('- Models: 6')
      end

      it 'auth_stack_line with devise' do
        auth = { authentication: { devise: ['User'] }, authorization: {} }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)).to eq('- Auth: Devise')
      end

      it 'auth_stack_line with multiple auth providers' do
        auth = { authentication: { devise: ['User'], rails_auth: true }, authorization: { pundit: ['Post'] } }
        line = RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)
        expect(line).to include('Devise')
        expect(line).to include('Rails 8 auth')
        expect(line).to include('Pundit')
      end

      it 'auth_stack_line with no auth' do
        auth = { authentication: {}, authorization: {} }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)).to be_nil
      end

      it 'auth_stack_line with malformed nested auth sections' do
        auth = { authentication: 'placeholder', authorization: ['placeholder'] }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)).to be_nil
      end

      it 'auth_stack_line ignores empty CanCanCan payloads' do
        auth = { authentication: {}, authorization: { cancancan: [] } }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)).to be_nil
      end

      it 'auth_stack_line includes populated CanCanCan payloads' do
        auth = { authentication: {}, authorization: { cancancan: ['Ability'] } }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(auth)).to eq('- Auth: CanCanCan')
      end

      it 'auth_stack_line with nil auth' do
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AuthStackBuilder.build(nil)).to be_nil
      end

      it 'async_stack_line with jobs only' do
        jobs = { jobs: [{ name: 'ProcessData' }], mailers: [], channels: [] }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AsyncStackBuilder.build(jobs)).to eq('- Async: 1 jobs')
      end

      it 'async_stack_line with mixed' do
        jobs = { jobs: [{ name: 'ProcessData' }], mailers: [{ name: 'WelcomeMailer' }], channels: [{ name: 'ChatChannel' }] }
        line = RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AsyncStackBuilder.build(jobs)
        expect(line).to include('1 jobs')
        expect(line).to include('1 mailers')
        expect(line).to include('1 channels')
      end

      it 'async_stack_line with empty async' do
        jobs = { jobs: [], mailers: [], channels: [] }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AsyncStackBuilder.build(jobs)).to be_nil
      end

      it 'async_stack_line with nil async' do
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::AsyncStackBuilder.build(nil)).to be_nil
      end

      it 'migrations_stack_line with pending' do
        migrations = { total: 20, pending: [{ filename: 'add_users.rb' }, { filename: 'create_posts.rb' }] }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::MigrationsStackBuilder.build(migrations)).to eq('- Migrations: 20 total, 2 pending')
      end

      it 'migrations_stack_line with no pending' do
        migrations = { total: 20, pending: [] }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::MigrationsStackBuilder.build(migrations)).to eq('- Migrations: 20 total, 0 pending')
      end

      it 'migrations_stack_line with nil pending' do
        migrations = { total: 20, pending: nil }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::MigrationsStackBuilder.build(migrations)).to eq('- Migrations: 20 total, 0 pending')
      end

      it 'migrations_stack_line with error' do
        migrations = { error: 'failed' }
        expect(RailsAiBridge::Serializers::Providers::Collaborators::StackOverviewBuilder::MigrationsStackBuilder.build(migrations)).to be_nil
      end
    end

    describe 'model line formatting' do
      it 'formats basic model line' do
        data = { associations: [], validations: [], enums: {}, table_name: 'users' }
        line = serializer.send(:model_line_formatter).format_line('User', data)
        expect(line).to eq('- **User**')
      end

      it 'includes associations and validations count' do
        data = { associations: [{ type: 'has_many', name: 'posts' }, { type: 'belongs_to', name: 'user' }], validations: [{ name: 'presence' }, { name: 'uniqueness' }], enums: {},
                 table_name: 'users' }
        line = serializer.send(:model_line_formatter).format_line('User', data)
        expect(line).to include('(2a, 2v)')
      end

      it 'includes enums' do
        data = { associations: [], validations: [], enums: { status: %w[active inactive] }, table_name: 'users' }
        line = serializer.send(:model_line_formatter).format_line('User', data)
        expect(line).to include('[enums: status]')
      end

      it 'includes top associations' do
        data = { associations: [{ type: 'has_many', name: 'posts' }, { type: 'belongs_to', name: 'user' }], validations: [], enums: {}, table_name: 'users' }
        line = serializer.send(:model_line_formatter).format_line('User', data)
        expect(line).to include('— has_many :posts, belongs_to :user')
      end

      it 'includes recently migrated flag' do
        data = { associations: [], validations: [], enums: {}, table_name: 'recently_migrated_table' }
        # Mock the ContextSummary.recently_migrated? method to return true
        allow(RailsAiBridge::Serializers::ContextSummary)
          .to receive(:recently_migrated?)
          .with('recently_migrated_table', anything)
          .and_return(true)
        line = serializer.send(:model_line_formatter).format_line('User', data)
        expect(line).to eq('- **User** [recently migrated]')
      end
    end
  end
end
