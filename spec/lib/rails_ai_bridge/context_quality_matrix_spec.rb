# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'
require_relative '../../support/real_fixture_app_context'

RSpec.describe 'rails-ai-bridge context quality matrix' do
  let(:model_entry) do
    lambda do |name, **options|
      [
        name,
        {
          table_name: options.fetch(:table) { name.underscore.pluralize },
          semantic_tier: options.fetch(:tier, 'supporting'),
          associations: options.fetch(:associations, 0).times.map { |index| { type: 'has_many', name: "rel_#{index}" } },
          validations: options.fetch(:validations, 0).times.map { |index| { kind: 'presence', attributes: ["attr_#{index}"] } }
        }
      ]
    end
  end

  let(:base_context) do
    default_schema = lambda do |models|
      {
        adapter: 'postgresql',
        total_tables: models.size,
        tables: models.values.index_by { |data| data[:table_name] }.transform_values do
          {
            primary_key: 'id',
            columns: [
              { name: 'id', type: 'integer' },
              { name: 'name', type: 'string' },
              { name: 'status', type: 'string' },
              { name: 'created_at', type: 'datetime' }
            ]
          }
        end
      }
    end

    lambda do |models:, routes:, controllers: {}, schema: nil, route_metadata: {}|
      {
        app_name: 'QualityFixture',
        rails_version: '8.0.0',
        ruby_version: RUBY_VERSION,
        generated_at: Time.now.iso8601,
        environment: 'test',
        schema: schema || default_schema.call(models),
        models: models,
        routes: { total_routes: routes.values.sum(&:size), by_controller: routes }.merge(route_metadata),
        controllers: { controllers: controllers },
        gems: { notable_gems: [{ name: 'devise', category: 'auth' }] },
        conventions: { architecture: ['mvc'], patterns: ['service_objects'] },
        tests: { framework: 'rspec' }
      }
    end
  end

  let(:large_models) do
    45.times.to_h do |index|
      model_entry.call("Model#{index}", associations: index % 7, validations: index % 4)
    end.merge(
      [model_entry.call('Account', tier: 'core_entity', associations: 4, validations: 2)].to_h
    )
  end

  let(:fixtures) do
    {
      standard_crud: base_context.call(
        models: [model_entry.call('User', tier: 'core_entity', associations: 3), model_entry.call('Post', associations: 2)].to_h,
        routes: { 'users' => 7.times.map { {} }, 'posts' => 7.times.map { {} } },
        controllers: { 'UsersController' => { actions: %w[index show] } }
      ),
      large_schema: base_context.call(
        models: large_models,
        routes: { 'accounts' => 9.times.map { {} }, 'reports' => 4.times.map { {} } }
      ),
      api_only: base_context.call(
        models: [model_entry.call('ApiToken', tier: 'core_entity', associations: 1)].to_h,
        routes: { 'api/v1/tokens' => 5.times.map { {} } },
        controllers: { 'Api::V1::TokensController' => { actions: %w[index create] } }
      ),
      hotwire: base_context.call(
        models: [model_entry.call('Message', tier: 'core_entity', associations: 2)].to_h,
        routes: { 'messages' => 8.times.map { {} } }
      ).merge(views: { templates: 12, partials: 9 }, stimulus: { controllers: 4 }),
      engine_style: base_context.call(
        models: [model_entry.call('Billing::Subscription', tier: 'core_entity', associations: 3)].to_h,
        routes: { 'billing/subscriptions' => 6.times.map { {} } },
        route_metadata: { mounted_engines: [{ engine: 'Billing::Engine', path: '/billing' }] }
      ),
      regulated: base_context.call(
        models: {},
        schema: { skipped: true, reason: 'domain metadata disabled' },
        routes: { 'health_checks' => [{}] }
      )
    }
  end

  let(:real_fixture_contexts) do
    {
      api_only_blog: RealFixtureAppContext.build(:api_only_blog),
      hotwire_crud: RealFixtureAppContext.build(:hotwire_crud),
      large_schema_crm: RealFixtureAppContext.build(:large_schema_crm)
    }
  end

  it 'generates bounded, actionable provider output for each fixture profile' do
    previous_mode = RailsAiBridge.configuration.context_mode
    RailsAiBridge.configuration.context_mode = :compact

    fixtures.each_value do |context|
      codex = RailsAiBridge::Serializers::Providers::CodexSerializer.new(context).call
      copilot = RailsAiBridge::Serializers::Providers::CopilotSerializer.new(context).call

      expect(codex.lines.size).to be <= 180
      expect(copilot.lines.size).to be <= 220
      expect(codex).to include('detail:"summary"')
      expect(copilot).to include('rails_get_routes(detail:"summary")')
      expect(codex).not_to include('rails-ai-bridge:omit-merge')
      expect(copilot).not_to match(/RAILS_AI_BRIDGE_MCP_TOKEN=\w+/)
    end
  ensure
    RailsAiBridge.configuration.context_mode = previous_mode
  end

  it 'keeps regulated output free of schema and model listings' do
    previous_mode = RailsAiBridge.configuration.context_mode
    RailsAiBridge.configuration.context_mode = :compact

    output = RailsAiBridge::Serializers::Providers::CodexSerializer.new(fixtures.fetch(:regulated)).call

    expect(output).to include('rails_get_model_details(detail:"summary")')
    expect(output).not_to include('Database:')
    expect(output).not_to include('## Models (')
  ensure
    RailsAiBridge.configuration.context_mode = previous_mode
  end

  it 'serializes large fixture output within a small benchmark budget' do
    elapsed = Benchmark.realtime do
      10.times { RailsAiBridge::Serializers::Providers::CodexSerializer.new(fixtures.fetch(:large_schema)).call }
    end

    expect(elapsed).to be < 0.5
  end

  it 'builds context from real API-only, Hotwire, and large-schema fixture app trees' do
    api_context = real_fixture_contexts.fetch(:api_only_blog)
    hotwire_context = real_fixture_contexts.fetch(:hotwire_crud)
    large_context = real_fixture_contexts.fetch(:large_schema_crm)

    expect(api_context.dig(:schema, :total_tables)).to eq(3)
    expect(api_context[:models]).to include('Article', 'ApiToken', 'User')
    expect(api_context.dig(:routes, :by_controller)).to include('api/v1/articles', 'api/v1/tokens')
    expect(api_context.dig(:controllers, :controllers)).to include('Api::V1::ArticlesController')

    expect(hotwire_context.dig(:schema, :total_tables)).to eq(2)
    expect(hotwire_context[:models]).to include('Conversation', 'Message')
    expect(hotwire_context.dig(:views, :templates)).to include('conversations')
    expect(hotwire_context.dig(:views, :partials, :per_controller)).to include('messages')
    expect(hotwire_context.dig(:stimulus, :controllers).first).to include(name: 'message')

    expect(large_context.dig(:schema, :total_tables)).to eq(16)
    expect(large_context[:models].keys).to include('Account', 'Customer', 'Invoice', 'Subscription')
    expect(large_context[:models].size).to eq(16)
    expect(large_context.dig(:routes, :by_controller)).to include('accounts', 'customers', 'opportunities')
  end

  it 'keeps generated output useful for real fixture app profiles' do
    previous_mode = RailsAiBridge.configuration.context_mode
    RailsAiBridge.configuration.context_mode = :compact

    real_fixture_contexts.each do |profile, context|
      codex = RailsAiBridge::Serializers::Providers::CodexSerializer.new(context).call
      cursor = RailsAiBridge::Serializers::Providers::CursorRulesSerializer.new(context).send(:render_project_rule)

      expect(codex.lines.size).to be <= 180
      expect(cursor.lines.size).to be <= 80
      expect(codex).to include('rails_get_routes(detail:"summary")')
      expect(cursor).to include('Endpoint focus')

      case profile
      when :api_only_blog
        expect(cursor).to include('api/v1/articles')
        expect(codex).to include('Article')
      when :hotwire_crud
        expect(cursor).to include('messages')
        expect(codex).to include('Conversation')
      when :large_schema_crm
        expect(cursor).to include('accounts')
        expect(codex).to include('Account')
        expect(codex).to include('rails_get_model_details')
      end
    end
  ensure
    RailsAiBridge.configuration.context_mode = previous_mode
  end

  it 'keeps real large-schema fixture output bounded and relevance ordered' do
    previous_mode = RailsAiBridge.configuration.context_mode
    RailsAiBridge.configuration.context_mode = :compact

    context = real_fixture_contexts.fetch(:large_schema_crm)
    codex = RailsAiBridge::Serializers::Providers::CodexSerializer.new(context).call

    expect(codex.lines.size).to be <= 180
    expect(codex).to include('...13 more')
    expect(codex.index('Account')).to be < codex.index('Customer')
  ensure
    RailsAiBridge.configuration.context_mode = previous_mode
  end
end
