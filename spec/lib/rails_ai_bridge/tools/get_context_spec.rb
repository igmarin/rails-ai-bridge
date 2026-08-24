# frozen_string_literal: true

require 'spec_helper'

# Composite tool fixtures need model/schema/controller/route/test snapshots.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe RailsAiBridge::Tools::GetContext do
  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }
  let(:params) { { model: 'User' } }
  let(:app_root) { Pathname.new(Dir.mktmpdir('get-context-')) }

  let(:models_data) do
    {
      'User' => {
        table_name: 'users',
        semantic_tier: 'core',
        semantic_tier_reason: 'listed in core_models',
        associations: [
          { name: 'posts', type: 'has_many', source: :reflection },
          { name: 'profile', type: 'has_one', source: :regex }
        ],
        validations: [{ kind: 'presence', attributes: ['email'], options: {} }]
      },
      'Post' => {
        table_name: 'posts',
        semantic_tier: 'supporting',
        associations: [{ name: 'user', type: 'belongs_to', source: :reflection }],
        validations: []
      }
    }
  end

  let(:schema_data) do
    {
      adapter: 'SQLite',
      source: :live,
      tables: {
        'users' => {
          columns: [
            { name: 'id', type: 'integer', null: false, default: nil },
            { name: 'email', type: 'string', null: false, default: nil },
            { name: 'name', type: 'string', null: true, default: nil }
          ],
          indexes: [{ name: 'index_users_on_email', columns: ['email'], unique: true }],
          foreign_keys: []
        },
        'posts' => {
          columns: [
            { name: 'id', type: 'integer', null: false, default: nil },
            { name: 'title', type: 'string', null: true, default: nil }
          ],
          indexes: [],
          foreign_keys: []
        }
      }
    }
  end

  let(:controllers_data) do
    {
      controllers: {
        'UsersController' => {
          parent_class: 'ApplicationController',
          actions: %w[index show create],
          filters: [{ kind: 'before_action', name: 'set_user', only: ['show'] }],
          strong_params: ['user_params']
        },
        'PostsController' => {
          parent_class: 'ApplicationController',
          actions: %w[index show],
          filters: [],
          strong_params: []
        }
      }
    }
  end

  let(:routes_data) do
    {
      total_routes: 4,
      api_namespaces: [],
      by_controller: {
        'users' => [
          { verb: 'GET', path: '/users', action: 'index', name: 'users' },
          { verb: 'GET', path: '/users/:id', action: 'show', name: 'user' }
        ],
        'posts' => [
          { verb: 'GET', path: '/posts', action: 'index', name: 'posts' },
          { verb: 'POST', path: '/posts', action: 'create', name: nil }
        ]
      }
    }
  end

  let(:tests_data) { { framework: 'rspec' } }

  before do
    FileUtils.mkdir_p(app_root.join('spec/models'))
    File.write(app_root.join('spec/models/user_spec.rb'), '# user spec')
    FileUtils.mkdir_p(app_root.join('spec/requests'))
    File.write(app_root.join('spec/requests/posts_spec.rb'), '# posts spec')

    allow(described_class).to receive(:rails_app).and_return(instance_double(Rails::Application, root: app_root))
    allow(described_class).to receive(:cached_section) do |section|
      case section
      when :models then models_data
      when :schema then schema_data
      when :controllers then controllers_data
      when :routes then routes_data
      when :tests then tests_data
      end
    end
  end

  after do
    FileUtils.remove_entry(app_root)
  end

  describe 'MCP definition' do
    it 'registers as rails_get_context' do
      expect(described_class.tool_name).to eq('rails_get_context')
    end

    it 'is annotated read-only and closed-world' do
      annotations = described_class.annotations_value
      expect(annotations.read_only_hint).to be(true)
      expect(annotations.open_world_hint).to be(false)
    end

    it 'is registered in Server::TOOLS' do
      expect(RailsAiBridge::Server::TOOLS).to include(described_class)
    end
  end

  describe '.call' do
    context 'when no model, controller, or feature is given' do
      let(:params) { {} }

      it 'returns a setup message requiring a name' do
        expect(content).to match(/at least one of.*model.*controller.*feature/i)
      end
    end

    context 'with model lookup' do
      let(:params) { { model: 'User' } }

      it 'returns table, model, routes, controller, and related tests' do
        expect(content).to include('users')
        expect(content).to include('User')
        expect(content).to include('has_many')
        expect(content).to include('posts')
        expect(content).to include('presence')
        expect(content).to include('core')
        expect(content).to include('/users')
        expect(content).to include('UsersController')
        expect(content).to include('index')
        expect(content).to include('set_user')
        expect(content).to include('spec/models/user_spec.rb')
      end

      it 'tags verified and inferred facts with ConfidenceTag' do
        expect(content).to include('[VERIFIED]')
        expect(content).to include('[INFERRED]')
      end

      it 'looks up models case-insensitively' do
        result = described_class.call(model: 'user')
        expect(result.content.first[:text]).to include('User')
      end
    end

    context 'with controller lookup' do
      let(:params) { { controller: 'PostsController' } }

      it 'returns matching controller actions, filters, routes, and related model/table' do
        expect(content).to include('PostsController')
        expect(content).to include('index')
        expect(content).to include('/posts')
        expect(content).to include('Post')
        expect(content).to include('posts')
      end
    end

    context 'with feature name resolution' do
      let(:params) { { feature: 'posts' } }

      it 'resolves an inflection-normalized feature to model, controller, table, and routes' do
        expect(content).to include('Post')
        expect(content).to include('PostsController')
        expect(content).to include('## Table')
        expect(content).to include('posts')
        expect(content).to include('/posts')
        expect(content).to include('spec/requests/posts_spec.rb')
      end

      it 'resolves a classified feature name' do
        result = described_class.call(feature: 'User')
        text = result.content.first[:text]
        expect(text).to include('User')
        expect(text).to include('UsersController')
        expect(text).to include('users')
      end
    end

    context 'when the name does not resolve' do
      let(:params) { { model: 'Missing' } }

      it 'returns a not-found message listing available models' do
        expect(content).to include('not found')
        expect(content).to include('User')
        expect(content).to include('Post')
      end
    end

    context 'when the requested model is excluded' do
      around do |example|
        original = RailsAiBridge.configuration.excluded_models.dup
        RailsAiBridge.configuration.excluded_models += ['User']
        example.run
      ensure
        RailsAiBridge.configuration.excluded_models = original
      end

      let(:params) { { model: 'User' } }

      it 'does not dump excluded model or table context' do
        expect(content).not_to include('has_many')
        expect(content).not_to include('index_users_on_email')
        expect(content).to match(/not found|excluded/i)
      end
    end

    context 'when the resolved table is excluded' do
      around do |example|
        original = RailsAiBridge.configuration.excluded_tables.dup
        RailsAiBridge.configuration.excluded_tables += ['users']
        example.run
      ensure
        RailsAiBridge.configuration.excluded_tables = original
      end

      let(:params) { { model: 'User' } }

      it 'omits the table section' do
        expect(content).not_to include('index_users_on_email')
        expect(content).not_to match(/## Table.*users/m)
      end

      it 'omits users routes as well as the table section' do
        expect(content).not_to include('/users')
      end
    end

    context 'when :regulated omits domain introspectors' do
      let(:models_data) { nil }
      let(:schema_data) { nil }
      let(:params) { { controller: 'PostsController' } }

      it 'returns a setup message for missing domain data and still includes the controller' do
        expect(content).to match(/not available|Add :models|Add :schema/i)
        expect(content).to include('PostsController')
        expect(content).to include('index')
      end
    end

    context 'when preset is :regulated but cached sections still contain schema' do
      around do |example|
        config = RailsAiBridge.configuration
        previous_preset = config.preset
        previous_introspectors = config.introspectors.dup
        config.preset = :regulated
        example.run
      ensure
        config.introspectors = previous_introspectors
        config.preset = previous_preset
      end

      let(:params) { { model: 'User' } }

      it 'does not dump schema or model facts' do
        expect(content).not_to include('index_users_on_email')
        expect(content).not_to include('has_many')
        expect(content).to match(/not available|Add :models|Add :schema|not found/i)
      end
    end

    context 'when feature is a path-traversal token' do
      let(:params) { { feature: '../../.env' } }

      it 'does not probe files outside the app root' do
        probed = []
        allow(File).to receive(:exist?).and_wrap_original do |original, path|
          probed << path.to_s
          original.call(path)
        end

        expect(content).not_to include('.env')
        expect(content).to match(/not found|Nothing matched/i)

        root = File.expand_path(app_root.to_s)
        probed.each do |path|
          expect(path).not_to include('..')
          expanded = File.expand_path(path)
          expect(expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")).to be(true)
        end
      end
    end

    context 'when nearby controller route keys share a substring' do
      let(:routes_data) do
        {
          total_routes: 3,
          api_namespaces: [],
          by_controller: {
            'users' => [{ verb: 'GET', path: '/users', action: 'index', name: 'users' }],
            'user_sessions' => [{ verb: 'GET', path: '/user_sessions', action: 'index', name: 'user_sessions' }],
            'superuser' => [{ verb: 'GET', path: '/superuser', action: 'show', name: 'superuser' }]
          }
        }
      end
      let(:params) { { feature: 'user' } }

      it 'does not attach user_sessions or superuser routes' do
        expect(content).to include('/users')
        expect(content).not_to include('user_sessions')
        expect(content).not_to include('/user_sessions')
        expect(content).not_to include('superuser')
        expect(content).not_to include('/superuser')
      end
    end

    context 'when the related model is excluded and a controller is requested' do
      around do |example|
        original = RailsAiBridge.configuration.excluded_models.dup
        RailsAiBridge.configuration.excluded_models += ['User']
        example.run
      ensure
        RailsAiBridge.configuration.excluded_models = original
      end

      let(:params) { { controller: 'UsersController' } }

      it 'does not attach routes for the excluded model' do
        expect(content).to include('UsersController')
        expect(content).not_to include('/users')
        expect(content).not_to include('has_many')
      end
    end

    context "with detail: 'summary'" do
      let(:models_data) do
        associations = 40.times.map { |i| { name: "assoc_#{i}", type: 'has_many', source: :reflection } }
        validations = 20.times.map { |i| { kind: 'presence', attributes: ["field_#{i}"], options: {} } }
        {
          'User' => {
            table_name: 'users',
            semantic_tier: 'core',
            associations: associations,
            validations: validations
          }
        }
      end

      let(:schema_data) do
        columns = 80.times.map { |i| { name: "col_#{i}", type: 'string', null: true, default: nil } }
        {
          adapter: 'SQLite',
          source: :live,
          tables: {
            'users' => { columns: columns, indexes: [], foreign_keys: [] }
          }
        }
      end

      let(:params) { { model: 'User', detail: 'summary' } }

      it 'stays small and does not dump every column or association' do
        expect(content.length).to be < 2500
        expect(content).not_to include('| col_40 |')
        expect(content).not_to include('assoc_39')
      end
    end

    context 'when max_tool_response_chars is set' do
      around do |example|
        original = RailsAiBridge.configuration.max_tool_response_chars
        RailsAiBridge.configuration.max_tool_response_chars = 80
        example.run
      ensure
        RailsAiBridge.configuration.max_tool_response_chars = original
      end

      let(:params) { { model: 'User', detail: 'full' } }

      it 'truncates through text_response' do
        expect(content).to include('Response truncated')
        expect(content.length).to be <= 80
      end
    end
  end

  describe '.app_root' do
    it 'returns nil when Rails.application is nil' do
      allow(described_class).to receive(:rails_app).and_return(nil)

      expect(described_class.app_root).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
