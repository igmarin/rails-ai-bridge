# frozen_string_literal: true

require 'spec_helper'
# rubocop:disable RSpec/MultipleMemoizedHelpers

# Branch-coverage specs for GetContext::Composer and GetContext::Resolver,
# exercised through the public +.call+ interface.
RSpec.describe RailsAiBridge::Tools::GetContext do
  let(:app_root) { Pathname.new(Dir.mktmpdir('get-context-branches-')) }

  before do
    allow(described_class).to receive(:rails_app).and_return(instance_double(Rails::Application, root: app_root))
  end

  after do
    FileUtils.remove_entry(app_root)
  end

  describe 'Composer branch coverage' do
    let(:composer) do
      RailsAiBridge::Tools::GetContext::Composer.new(resolution: resolution, snapshots: snapshots,
                                                     detail: detail, test_paths: test_paths)
    end

    let(:snapshots) { {} }
    let(:test_paths) { [] }

    context 'with hard error (nothing resolved)' do
      let(:resolution) do
        { error: 'Nothing matched feature foo', model_name: nil, controller_name: nil, table_name: nil,
          setup_messages: ['Schema introspection not available.'], requested_feature: 'foo' }
      end
      let(:detail) { 'summary' }

      it 'returns error and setup messages' do
        result = composer.call
        expect(result).to include('Nothing matched feature foo')
        expect(result).to include('Schema introspection not available.')
      end
    end

    context 'with model data nil' do
      let(:resolution) do
        { model_name: 'Ghost', model_data: nil, table_name: nil, table_data: nil,
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_model: 'Ghost' }
      end
      let(:detail) { 'summary' }

      it 'renders model-not-found message' do
        result = composer.call
        expect(result).to include("Model 'Ghost' has no introspection payload")
      end
    end

    context 'with model data error' do
      let(:resolution) do
        { model_name: 'Broken', model_data: { error: 'load failed' },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil,
          routes: {}, setup_messages: [], schema_source: :live, requested_model: 'Broken' }
      end
      let(:detail) { 'summary' }

      it 'renders model error message' do
        result = composer.call
        expect(result).to include('Error inspecting Broken: load failed')
      end
    end

    context 'with table data nil in full detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: 'ghost_table', table_data: nil,
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :static, requested_feature: 'ghost' }
      end
      let(:detail) { 'full' }

      it 'renders table name with confidence tag but no columns' do
        result = composer.call
        expect(result).to include('## Table')
        expect(result).to include('ghost_table')
      end
    end

    context 'with table data present in full detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil,
          table_name: 'users', table_data: { columns: [{ name: 'id', type: 'integer' }], indexes: [] },
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_feature: 'users' }
      end
      let(:detail) { 'full' }

      it 'renders full table with columns' do
        result = composer.call
        expect(result).to include('## Table')
        expect(result).to include('| id | integer |')
      end
    end

    context 'with table in standard detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil,
          table_name: 'users', table_data: { columns: [{ name: 'id', type: 'integer' }] },
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_feature: 'users' }
      end
      let(:detail) { 'standard' }

      it 'renders standard table with column signatures' do
        result = composer.call
        expect(result).to include('id:integer')
      end
    end

    context 'with table in summary detail and no data' do
      let(:resolution) do
        { model_name: nil, model_data: nil,
          table_name: 'users', table_data: nil,
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_feature: 'users' }
      end
      let(:detail) { 'summary' }

      it 'renders table with 0 columns and 0 indexes' do
        result = composer.call
        expect(result).to include('0 columns, 0 indexes')
      end
    end

    context 'with model in full detail' do
      let(:resolution) do
        { model_name: 'User', model_data: { table_name: 'users', associations: [{ type: 'has_many', name: 'posts', source: :reflection }], validations: [] },
          table_name: 'users', table_data: { columns: [{ name: 'id', type: 'integer' }] },
          controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_model: 'User' }
      end
      let(:detail) { 'full' }

      it 'renders full model detail via SingleModelFormatter' do
        result = composer.call
        expect(result).to include('# User')
        expect(result).to include('has_many')
      end
    end

    context 'with model in standard detail' do
      let(:resolution) do
        { model_name: 'User',
          model_data: { table_name: 'users', semantic_tier: 'core', semantic_tier_reason: 'central',
                        associations: [{ type: 'has_many', name: 'posts', source: :reflection }],
                        validations: [{ kind: 'presence', attributes: ['name'] }] },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_model: 'User' }
      end
      let(:detail) { 'standard' }

      it 'renders standard model with table, tier, associations, and validations' do
        result = composer.call
        expect(result).to include('# User')
        expect(result).to include('**Table:** `users`')
        expect(result).to include('**Semantic tier:** `core`')
        expect(result).to include('**Tier reason:** central')
        expect(result).to include('## Associations')
        expect(result).to include('## Validations')
      end
    end

    context 'with model in summary detail with semantic tier' do
      let(:resolution) do
        { model_name: 'User',
          model_data: { associations: [{ type: 'has_many', name: 'posts', source: :reflection }],
                        validations: [{ kind: 'presence', attributes: ['name'] }], semantic_tier: 'core' },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil, routes: {},
          setup_messages: [], schema_source: :live, requested_model: 'User' }
      end
      let(:detail) { 'summary' }

      it 'renders summary model with tier and limited associations/validations' do
        result = composer.call
        expect(result).to include('tier: `core`')
        expect(result).to include('1 associations, 1 validations')
        expect(result).to include('`has_many` **posts**')
        expect(result).to include('`presence` on name')
      end
    end

    context 'with routes in summary detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: nil, table_data: nil,
          controller_name: nil, controller_data: nil,
          routes: { 'users' => [{ path: '/users', verb: 'GET', action: 'index' }, { path: '/users/:id', verb: 'GET', action: 'show' }] },
          setup_messages: [], schema_source: nil, requested_feature: 'users' }
      end
      let(:detail) { 'summary' }

      it 'renders routes summary with sample paths' do
        result = composer.call
        expect(result).to include('## Routes')
        expect(result).to include('**users** — 2 routes')
        expect(result).to include('`/users`')
      end
    end

    context 'with routes in standard detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: nil, table_data: nil,
          controller_name: nil, controller_data: nil,
          routes: { 'users' => [{ path: '/users', verb: 'GET', action: 'index', name: 'users' }] },
          setup_messages: [], schema_source: nil, requested_feature: 'users' }
      end
      let(:detail) { 'standard' }

      it 'renders routes with paths and actions' do
        result = composer.call
        expect(result).to include('## Routes')
        expect(result).to include('### users')
        expect(result).to include('`/users` → index')
      end
    end

    context 'with controller data error' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: nil, table_data: nil,
          controller_name: 'BrokenController', controller_data: { error: 'load failed' },
          routes: {}, setup_messages: [], schema_source: nil, requested_controller: 'BrokenController' }
      end
      let(:detail) { 'summary' }

      it 'renders controller error message' do
        result = composer.call
        expect(result).to include('Error inspecting BrokenController: load failed')
      end
    end

    context 'with controller data nil' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: nil, table_data: nil,
          controller_name: 'GhostController', controller_data: nil,
          routes: {}, setup_messages: [], schema_source: nil, requested_controller: 'GhostController' }
      end
      let(:detail) { 'summary' }

      it 'renders controller-not-found message' do
        result = composer.call
        expect(result).to include('_No payload for GhostController._')
      end
    end

    context 'with controller in full detail' do
      let(:resolution) do
        { model_name: nil, model_data: nil, table_name: nil, table_data: nil,
          controller_name: 'UsersController',
          controller_data: { parent_class: 'ApplicationController', actions: %w[index show], filters: [{ kind: 'before', name: 'auth' }], strong_params: ['user_params'] },
          routes: {}, setup_messages: [], schema_source: nil, requested_controller: 'UsersController' }
      end
      let(:detail) { 'full' }

      it 'renders full controller detail' do
        result = composer.call
        expect(result).to include('# UsersController')
        expect(result).to include('**Parent:** `ApplicationController`')
        expect(result).to include('## Actions')
        expect(result).to include('## Filters')
        expect(result).to include('## Strong Params')
      end
    end

    context 'with test paths in summary detail' do
      let(:resolution) do
        { model_name: 'User', model_data: { associations: [], validations: [] },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil,
          routes: {}, setup_messages: [], schema_source: nil, requested_model: 'User' }
      end
      let(:test_paths) { %w[spec/models/user_spec.rb spec/requests/users_spec.rb] }
      let(:detail) { 'summary' }

      it 'renders test paths with limit' do
        result = composer.call
        expect(result).to include('## Related tests')
        expect(result).to include('spec/models/user_spec.rb')
      end
    end

    context 'with test paths in full detail' do
      let(:resolution) do
        { model_name: 'User', model_data: { associations: [], validations: [] },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil,
          routes: {}, setup_messages: [], schema_source: nil, requested_model: 'User' }
      end
      let(:test_paths) { %w[spec/models/user_spec.rb spec/requests/users_spec.rb spec/system/users_spec.rb] }
      let(:detail) { 'full' }

      it 'renders all test paths' do
        result = composer.call
        expect(result).to include('## Related tests')
        expect(result).to include('spec/system/users_spec.rb')
      end
    end

    context 'with invalid detail level' do
      let(:resolution) do
        { model_name: 'User', model_data: { associations: [], validations: [] },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil,
          routes: {}, setup_messages: [], schema_source: nil, requested_model: 'User' }
      end
      let(:detail) { 'bogus' }

      it 'falls back to summary' do
        result = composer.call
        expect(result).to include('# Context: User')
      end
    end

    context 'with setup messages and resolved model' do
      let(:resolution) do
        { model_name: 'User', model_data: { associations: [], validations: [] },
          table_name: nil, table_data: nil, controller_name: nil, controller_data: nil,
          routes: {}, setup_messages: ['Schema introspection not available.'], schema_source: nil,
          requested_model: 'User' }
      end
      let(:detail) { 'summary' }

      it 'includes setup messages in output' do
        result = composer.call
        expect(result).to include('Schema introspection not available.')
      end
    end
  end

  describe 'Resolver branch coverage' do
    let(:config) { RailsAiBridge.configuration }

    let(:snapshots) do
      {
        models: { 'User' => { table_name: 'users', associations: [], validations: [] }, 'Post' => { table_name: 'posts' } },
        schema: { source: :live, tables: { 'users' => { columns: [] }, 'posts' => { columns: [] } } },
        controllers: { controllers: { 'UsersController' => { actions: ['index'] }, 'PostsController' => { actions: ['index'] } } },
        routes: { by_controller: { 'users' => [{ verb: 'GET', path: '/users', action: 'index' }] } }
      }
    end

    let(:resolver) do
      RailsAiBridge::Tools::GetContext::Resolver.new(model: model, controller: controller, feature: feature,
                                                     snapshots: snapshots, config: config)
    end

    context 'when schema has adapter but no source key' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { adapter: 'PostgreSQL', tables: { 'users' => { columns: [] } } },
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'infers schema source as :live from adapter' do
        result = resolver.call
        expect(result[:schema_source]).to eq(:live)
      end
    end

    context 'when schema has static_parse adapter' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { adapter: 'static_parse', tables: { 'users' => { columns: [] } } },
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'infers schema source as :static' do
        result = resolver.call
        expect(result[:schema_source]).to eq(:static)
      end
    end

    context 'when schema has no adapter and no source' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { tables: { 'users' => { columns: [] } } },
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'returns nil schema source' do
        result = resolver.call
        expect(result[:schema_source]).to be_nil
      end
    end

    context 'when models section has error' do
      let(:model) { nil }
      let(:controller) { 'UsersController' }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { error: 'models failed' },
          schema: { source: :live, tables: {} },
          controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
          routes: { by_controller: {} }
        }
      end

      it 'includes model error in setup messages' do
        result = resolver.call
        expect(result[:setup_messages]).to include('Model introspection failed: models failed')
      end
    end

    context 'when schema section has error' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { error: 'schema failed' },
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'includes schema error in setup messages' do
        result = resolver.call
        expect(result[:setup_messages]).to include('Schema introspection not available: schema failed')
      end
    end

    context 'when nothing resolves and only controller was given' do
      let(:model) { nil }
      let(:controller) { 'MissingController' }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { source: :live, tables: { 'users' => { columns: [] } } },
          controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
          routes: { by_controller: {} }
        }
      end

      it 'returns controller not found error' do
        result = resolver.call
        expect(result[:error]).to include("Controller 'MissingController' not found")
        expect(result[:error]).to include('UsersController')
      end
    end

    context 'when nothing resolves and only feature was given' do
      let(:model) { nil }
      let(:controller) { nil }
      let(:feature) { 'nonexistent' }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: { source: :live, tables: { 'users' => { columns: [] } } },
          controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
          routes: { by_controller: {} }
        }
      end

      it 'returns nothing matched error with available models and controllers' do
        result = resolver.call
        expect(result[:error]).to include("Nothing matched feature 'nonexistent'")
        expect(result[:error]).to include('User')
        expect(result[:error]).to include('UsersController')
      end
    end

    context 'when models section is missing' do
      let(:model) { nil }
      let(:controller) { 'UsersController' }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: nil,
          schema: { source: :live, tables: {} },
          controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
          routes: { by_controller: {} }
        }
      end

      it 'includes model not available setup message' do
        result = resolver.call
        expect(result[:setup_messages]).to include('Model introspection not available. Add :models to introspectors.')
      end
    end

    context 'when schema section is missing' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: { 'User' => { table_name: 'users' } },
          schema: nil,
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'includes schema not available setup message' do
        result = resolver.call
        expect(result[:setup_messages]).to include('Schema introspection not available. Add :schema to introspectors.')
      end
    end

    context 'when controller is inferred from model' do
      let(:model) { 'User' }
      let(:controller) { nil }
      let(:feature) { nil }

      it 'infers controller from model name' do
        result = resolver.call
        expect(result[:controller_name]).to eq('UsersController')
      end
    end

    context 'when model is inferred from controller' do
      let(:model) { nil }
      let(:controller) { 'UsersController' }
      let(:feature) { nil }

      it 'infers model from controller name' do
        result = resolver.call
        expect(result[:model_name]).to eq('User')
      end
    end

    context 'when feature resolves to controller only (no model)' do
      let(:model) { nil }
      let(:controller) { nil }
      let(:feature) { 'users_controller' }
      let(:snapshots) do
        {
          models: {},
          schema: { source: :live, tables: {} },
          controllers: { controllers: { 'UsersController' => { actions: ['index'] } } },
          routes: { by_controller: { 'users' => [{ verb: 'GET', path: '/users', action: 'index' }] } }
        }
      end

      it 'resolves controller from feature' do
        result = resolver.call
        expect(result[:controller_name]).to eq('UsersController')
        expect(result[:routes]).not_to be_empty
      end
    end

    context 'with invalid name containing path traversal' do
      let(:model) { '../etc/passwd' }
      let(:controller) { nil }
      let(:feature) { nil }

      it 'shows invalid name in error message' do
        result = resolver.call
        expect(result[:error]).to include('(invalid name)')
      end
    end

    context 'with invalid name containing backslash' do
      let(:model) { nil }
      let(:controller) { 'foo\\bar' }
      let(:feature) { nil }
      let(:snapshots) do
        {
          models: {},
          schema: {},
          controllers: { controllers: {} },
          routes: { by_controller: {} }
        }
      end

      it 'shows invalid name in error message' do
        result = resolver.call
        expect(result[:error]).to include('(invalid name)')
      end
    end
  end

  describe 'RelatedTests branch coverage' do
    let(:root) { Pathname.new(Dir.mktmpdir('related-tests-')) }

    after do
      FileUtils.remove_entry(root)
    end

    it 'returns empty when root is nil' do
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: nil, resolution: { model_name: 'User' })
      expect(finder.paths).to eq([])
    end

    it 'finds conventional spec paths for a model' do
      FileUtils.mkdir_p(root.join('spec/models'))
      File.write(root.join('spec/models/user_spec.rb'), '# user spec')
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { model_name: 'User' })
      expect(finder.paths).to include('spec/models/user_spec.rb')
    end

    it 'finds conventional test paths for a controller' do
      FileUtils.mkdir_p(root.join('test/controllers'))
      File.write(root.join('test/controllers/users_controller_test.rb'), '# test')
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { controller_name: 'UsersController' })
      expect(finder.paths).to include('test/controllers/users_controller_test.rb')
    end

    it 'finds paths using table name' do
      FileUtils.mkdir_p(root.join('spec/requests'))
      File.write(root.join('spec/requests/users_spec.rb'), '# test')
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { table_name: 'users' })
      expect(finder.paths).to include('spec/requests/users_spec.rb')
    end

    it 'finds paths using feature name' do
      FileUtils.mkdir_p(root.join('spec/system'))
      File.write(root.join('spec/system/posts_spec.rb'), '# test')
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { requested_feature: 'posts' })
      expect(finder.paths).to include('spec/system/posts_spec.rb')
    end

    it 'ignores unsafe tokens' do
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { requested_feature: '../etc/passwd' })
      expect(finder.paths).to eq([])
    end

    it 'handles blank controller name' do
      finder = RailsAiBridge::Tools::GetContext::RelatedTests.new(root: root, resolution: { controller_name: '' })
      expect(finder.paths).to eq([])
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
