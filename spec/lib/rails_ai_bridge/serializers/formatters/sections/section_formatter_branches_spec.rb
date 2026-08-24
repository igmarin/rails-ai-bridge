# frozen_string_literal: true

require 'spec_helper'

# Branch-coverage specs for serializer section formatters. Each formatter is
# exercised through its public +.call+ interface with both present and
# missing/nil data to cover safe-navigation and early-return branches.
RSpec.describe RailsAiBridge::Serializers::Formatters::Sections do
  # :reek:UtilityFunction
  def render(klass, ctx)
    klass.new(ctx).call
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::MiddlewareFormatter do
    it 'renders custom middleware with detected patterns' do
      ctx = { middleware: { custom_middleware: [
        { class_name: 'CorsMiddleware', file: 'app/middleware/cors.rb', detected_patterns: %w[CORS Rack] }
      ] } }
      result = render(described_class, ctx)
      expect(result).to include('`CorsMiddleware`')
      expect(result).to include('CORS, Rack')
    end

    it 'renders custom middleware without detected patterns' do
      ctx = { middleware: { custom_middleware: [
        { class_name: 'SimpleMiddleware', file: 'app/middleware/simple.rb' }
      ] } }
      result = render(described_class, ctx)
      expect(result).to include('`SimpleMiddleware`')
      expect(result).not_to include('—')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::SeedsFormatter do
    it 'renders seeds file details with faker and environment conditional' do
      ctx = { seeds: {
        seeds_file: { exists: true, uses_faker: true, environment_conditional: true },
        models_seeded: %w[User Post],
        seed_files: [{ file: 'db/seeds.rb' }, { file: 'db/seeds/production.rb' }]
      } }
      result = render(described_class, ctx)
      expect(result).to include('Seeds file: exists')
      expect(result).to include('Uses Faker: yes')
      expect(result).to include('Environment-conditional: yes')
      expect(result).to include('Models seeded: User, Post')
      expect(result).to include('Seed Files')
      expect(result).to include('db/seeds/production.rb')
    end

    it 'renders seeds file as missing' do
      ctx = { seeds: { seeds_file: { exists: false } } }
      result = render(described_class, ctx)
      expect(result).to include('Seeds file: missing')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::ActiveStorageFormatter do
    it 'returns nil when no models or services' do
      expect(render(described_class, { active_storage: { models: [], services: [] } })).to be_nil
    end

    it 'renders services only' do
      ctx = { active_storage: { models: [], services: %w[local s3] } }
      result = render(described_class, ctx)
      expect(result).to include('Services:')
      expect(result).to include('`local`')
      expect(result).not_to include('Attached to')
    end

    it 'renders both models and services' do
      ctx = { active_storage: { models: ['User'], services: ['s3'] } }
      result = render(described_class, ctx)
      expect(result).to include('Attached to:')
      expect(result).to include('Services:')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::AuthFormatter do
    it 'returns nil when no strategies or models' do
      expect(render(described_class, { auth: { strategies: [], models: [] } })).to be_nil
    end

    it 'renders models only' do
      ctx = { auth: { strategies: [], models: ['User'] } }
      result = render(described_class, ctx)
      expect(result).to include('AuthN models:')
      expect(result).not_to include('Strategies:')
    end

    it 'renders both strategies and models' do
      ctx = { auth: { strategies: ['devise'], models: ['User'] } }
      result = render(described_class, ctx)
      expect(result).to include('Strategies:')
      expect(result).to include('AuthN models:')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::DevopsFormatter do
    it 'returns nil when no devops data' do
      expect(render(described_class, { devops: {} })).to be_nil
    end

    it 'renders docker, kamal, procfile, and health check' do
      ctx = { devops: {
        ci_cd: ['GitHub Actions'],
        docker: 'Dockerfile',
        kamal: true,
        procfile_entries: [{ name: 'web', command: 'bundle exec puma' }],
        health_check_route: '/health'
      } }
      result = render(described_class, ctx)
      expect(result).to include('**Docker:**')
      expect(result).to include('**Kamal:** yes')
      expect(result).to include('Procfile')
      expect(result).to include('web: bundle exec puma')
      expect(result).to include('Health Check')
      expect(result).to include('/health')
    end

    it 'renders with only docker' do
      ctx = { devops: { docker: 'Dockerfile' } }
      result = render(described_class, ctx)
      expect(result).to include('**Docker:**')
      expect(result).not_to include('**Kamal:**')
      expect(result).not_to include('Health Check')
    end

    it 'renders with only kamal' do
      ctx = { devops: { kamal: true } }
      result = render(described_class, ctx)
      expect(result).to include('**Kamal:** yes')
      expect(result).not_to include('**Docker:**')
      expect(result).not_to include('Health Check')
    end

    it 'renders with only health check route' do
      ctx = { devops: { health_check_route: '/up' } }
      result = render(described_class, ctx)
      expect(result).to include('Health Check')
      expect(result).not_to include('**Docker:**')
      expect(result).not_to include('**Kamal:**')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::TurboFormatter do
    it 'returns nil when all turbo data empty' do
      ctx = { turbo: { turbo_frames: [], turbo_streams: [], model_broadcasts: [] } }
      expect(render(described_class, ctx)).to be_nil
    end

    it 'renders turbo frames' do
      ctx = { turbo: { turbo_frames: [{ id: 'modal', file: 'app/views/posts/_modal.html.erb' }],
                       turbo_streams: [], model_broadcasts: [] } }
      result = render(described_class, ctx)
      expect(result).to include('Turbo Frames')
      expect(result).to include('modal')
    end

    it 'renders model broadcasts' do
      ctx = { turbo: { turbo_frames: [], turbo_streams: [], model_broadcasts: [
        { model: 'Post', methods: ['broadcast_replace'] }
      ] } }
      result = render(described_class, ctx)
      expect(result).to include('Model Broadcasts')
      expect(result).to include('Post')
      expect(result).to include('broadcast_replace')
    end

    it 'renders heading when all turbo keys are nil' do
      ctx = { turbo: { turbo_frames: nil, turbo_streams: nil, model_broadcasts: nil } }
      result = render(described_class, ctx)
      expect(result).to include('Hotwire / Turbo')
      expect(result).not_to include('Turbo Frames')
      expect(result).not_to include('Turbo Stream')
      expect(result).not_to include('Model Broadcasts')
    end

    it 'renders broadcasts when turbo_streams key is nil' do
      ctx = { turbo: { turbo_frames: [], turbo_streams: nil, model_broadcasts: [
        { model: 'Comment', methods: ['broadcast_append'] }
      ] } }
      result = render(described_class, ctx)
      expect(result).to include('Model Broadcasts')
      expect(result).not_to include('Turbo Stream Templates')
    end

    it 'renders streams when model_broadcasts key is nil' do
      ctx = { turbo: { turbo_frames: [], turbo_streams: ['comments/create'], model_broadcasts: nil } }
      result = render(described_class, ctx)
      expect(result).to include('Turbo Stream Templates')
      expect(result).not_to include('Model Broadcasts')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::ActionMailboxFormatter do
    it 'returns nil when no mailboxes' do
      expect(render(described_class, { action_mailbox: { mailboxes: [] } })).to be_nil
    end

    it 'returns nil when mailboxes key is nil' do
      expect(render(described_class, { action_mailbox: { mailboxes: nil } })).to be_nil
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::ActionTextFormatter do
    it 'returns nil when no models' do
      expect(render(described_class, { action_text: { models: [] } })).to be_nil
    end

    it 'returns nil when models key is nil' do
      expect(render(described_class, { action_text: { models: nil } })).to be_nil
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::ApiFormatter do
    it 'returns nil when no endpoints' do
      expect(render(described_class, { api: { endpoints: [] } })).to be_nil
    end

    it 'renders version, base path, and documentation url' do
      ctx = { api: {
        version: 'v1',
        base_path: '/api/v1',
        documentation_url: 'https://docs.example.com',
        endpoints: [{ verb: 'GET', path: '/widgets', controller: 'Widgets', action: 'index' }]
      } }
      result = render(described_class, ctx)
      expect(result).to include('Version: `v1`')
      expect(result).to include('Base path: `/api/v1`')
      expect(result).to include('Documentation: [https://docs.example.com]')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::AssetsFormatter do
    it 'returns nil when no asset data' do
      expect(render(described_class, { assets: {} })).to be_nil
    end

    it 'renders js bundler, importmap pins, css framework, and manifest files' do
      ctx = { assets: {
        precompiler: 'sprockets',
        js_bundler: 'esbuild',
        importmap_pins: %w[application controllers],
        css_framework: 'tailwindcss',
        manifest_files: ['app/assets/config/manifest.js']
      } }
      result = render(described_class, ctx)
      expect(result).to include('JavaScript bundler:')
      expect(result).to include('Importmap pins:')
      expect(result).to include('`application`')
      expect(result).to include('CSS framework:')
      expect(result).to include('Manifest files:')
    end

    it 'renders with only js bundler' do
      ctx = { assets: { js_bundler: 'esbuild' } }
      result = render(described_class, ctx)
      expect(result).to include('JavaScript bundler:')
      expect(result).not_to include('CSS framework:')
    end

    it 'renders with only css framework' do
      ctx = { assets: { css_framework: 'tailwindcss' } }
      result = render(described_class, ctx)
      expect(result).to include('CSS framework:')
      expect(result).not_to include('JavaScript bundler:')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::EnginesFormatter do
    it 'returns nil when no mounted engines' do
      expect(render(described_class, { engines: { mounted: [] } })).to be_nil
    end

    it 'returns nil when mounted key is nil' do
      expect(render(described_class, { engines: { mounted: nil } })).to be_nil
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::I18nFormatter do
    it 'returns nil when no locales' do
      expect(render(described_class, { i18n: { locales: [] } })).to be_nil
    end

    it 'returns nil when locales key is nil' do
      expect(render(described_class, { i18n: { locales: nil } })).to be_nil
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::MultiDatabaseFormatter do
    it 'returns nil when multi_db is false' do
      expect(render(described_class, { multi_database: { multi_db: false } })).to be_nil
    end

    it 'renders databases with replica flag' do
      ctx = { multi_database: {
        multi_db: true,
        databases: [
          { name: 'primary', adapter: 'postgresql', replica: false },
          { name: 'replica', adapter: 'postgresql', replica: true }
        ]
      } }
      result = render(described_class, ctx)
      expect(result).to include('`primary` — postgresql')
      expect(result).to include('`replica` — postgresql (replica)')
    end

    it 'renders model connections with and without connects_to' do
      ctx = { multi_database: {
        multi_db: true,
        databases: [],
        model_connections: [
          { model: 'User', connects_to: 'replica' },
          { model: 'AuditLog', connects_to: nil }
        ]
      } }
      result = render(described_class, ctx)
      expect(result).to include('Model Connections')
      expect(result).to include('`User` → replica')
      expect(result).to include('`AuditLog` → custom connection')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::RakeTasksFormatter do
    it 'returns nil when no tasks' do
      expect(render(described_class, { rake_tasks: { tasks: [] } })).to be_nil
    end

    it 'renders tasks with and without descriptions' do
      ctx = { rake_tasks: { tasks: [
        { name: 'db:migrate', description: 'Migrate the database' },
        { name: 'db:seed', description: nil }
      ] } }
      result = render(described_class, ctx)
      expect(result).to include('`db:migrate` — Migrate the database')
      expect(result).to include('`db:seed`')
      expect(result).not_to include('`db:seed` —')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::RoutesFormatter do
    it 'renders routes grouped by controller with actions' do
      ctx = { routes: {
        total_routes: 2,
        by_controller: {
          'UsersController' => [{ verb: 'GET', path: '/users', action: 'index' }],
          'PostsController' => [{ verb: 'POST', path: '/posts', action: 'create' }]
        }
      } }
      result = render(described_class, ctx)
      expect(result).to include('### UsersController')
      expect(result).to include('`GET /users` → index')
      expect(result).to include('### PostsController')
    end

    it 'renders heading when by_controller is nil' do
      ctx = { routes: { total_routes: 0 } }
      result = render(described_class, ctx)
      expect(result).to include('Routes (0 total)')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::SchemaFormatter do
    it 'renders tables with nil columns gracefully' do
      ctx = { schema: {
        total_tables: 1,
        tables: { 'users' => { columns: nil } }
      } }
      result = render(described_class, ctx)
      expect(result).to include('### users')
    end

    it 'renders multiple tables with columns' do
      ctx = { schema: {
        total_tables: 2,
        tables: {
          'users' => { columns: [{ name: 'id', type: 'integer' }, { name: 'email', type: 'string' }] },
          'posts' => { columns: [{ name: 'id', type: 'integer' }] }
        }
      } }
      result = render(described_class, ctx)
      expect(result).to include('### users')
      expect(result).to include('`id` (integer)')
      expect(result).to include('`email` (string)')
      expect(result).to include('### posts')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::TestsFormatter do
    it 'renders all test details' do
      ctx = { tests: {
        framework: 'RSpec',
        factories: { location: 'spec/factories', count: 5 },
        fixtures: { location: 'spec/fixtures', count: 3 },
        system_tests: { location: 'spec/system' },
        ci_config: ['GitHub Actions', 'CircleCI'],
        coverage: 'SimpleCov 95%'
      } }
      result = render(described_class, ctx)
      expect(result).to include('Framework: RSpec')
      expect(result).to include('Factories: spec/factories (5 files)')
      expect(result).to include('Fixtures: spec/fixtures (3 files)')
      expect(result).to include('System tests: spec/system')
      expect(result).to include('CI: GitHub Actions, CircleCI')
      expect(result).to include('Coverage: SimpleCov 95%')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::JobsFormatter do
    it 'returns nil when no adapter and no jobs' do
      expect(render(described_class, { jobs: { total_jobs: 0 } })).to be_nil
    end

    it 'renders with adapter only' do
      ctx = { jobs: { total_jobs: 0, adapter: 'sidekiq' } }
      result = render(described_class, ctx)
      expect(result).to include('Adapter: `sidekiq`')
      expect(result).not_to include('Defined Jobs')
    end

    it 'renders with jobs only (no adapter)' do
      ctx = { jobs: { total_jobs: 2, jobs: %w[FooJob BarJob] } }
      result = render(described_class, ctx)
      expect(result).to include('Defined Jobs')
      expect(result).to include('`FooJob`')
      expect(result).not_to include('Adapter')
    end
  end

  describe RailsAiBridge::Serializers::Formatters::Sections::ConfigFormatter do
    it 'returns nil when no config data' do
      expect(render(described_class, { config: {} })).to be_nil
    end

    it 'renders all config details' do
      ctx = { config: {
        cache_store: ':redis_cache_store',
        session_store: ':cookie_store',
        timezone: 'UTC',
        middleware_stack: %w[Rack::Cors Rack::Attack],
        initializers: %w[devise.rb sidekiq.rb],
        current_attributes: ['Current.user']
      } }
      result = render(described_class, ctx)
      expect(result).to include('Cache store:')
      expect(result).to include('Session store:')
      expect(result).to include('Timezone:')
      expect(result).to include('Middleware Stack')
      expect(result).to include('`Rack::Cors`')
      expect(result).to include('Initializers')
      expect(result).to include('`devise.rb`')
      expect(result).to include('CurrentAttributes')
      expect(result).to include('`Current.user`')
    end

    it 'renders with only session store' do
      ctx = { config: { session_store: ':cookie_store' } }
      result = render(described_class, ctx)
      expect(result).to include('Session store:')
      expect(result).not_to include('Cache store:')
    end

    it 'renders with only timezone' do
      ctx = { config: { timezone: 'UTC' } }
      result = render(described_class, ctx)
      expect(result).to include('Timezone:')
      expect(result).not_to include('Session store:')
    end

    it 'renders with only middleware stack' do
      ctx = { config: { middleware_stack: ['Rack::Cors'] } }
      result = render(described_class, ctx)
      expect(result).to include('Middleware Stack')
      expect(result).not_to include('Timezone:')
    end

    it 'renders with only initializers' do
      ctx = { config: { initializers: ['devise.rb'] } }
      result = render(described_class, ctx)
      expect(result).to include('Initializers')
      expect(result).not_to include('Middleware Stack')
    end

    it 'renders with only current attributes' do
      ctx = { config: { current_attributes: ['Current.user'] } }
      result = render(described_class, ctx)
      expect(result).to include('CurrentAttributes')
      expect(result).not_to include('Initializers')
    end
  end
end
