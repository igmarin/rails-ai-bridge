# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

RSpec.describe 'rails-ai-bridge context quality matrix' do
  def model(name, tier: 'supporting', table: nil, associations: 0, validations: 0)
    [
      name,
      {
        table_name: table || name.underscore.pluralize,
        semantic_tier: tier,
        associations: associations.times.map { |i| { type: 'has_many', name: "rel_#{i}" } },
        validations: validations.times.map { |i| { kind: 'presence', attributes: ["attr_#{i}"] } }
      }
    ]
  end

  def base_context(models:, routes:, controllers: {}, schema: nil, route_metadata: {})
    {
      app_name: 'QualityFixture',
      rails_version: '8.0.0',
      ruby_version: RUBY_VERSION,
      generated_at: Time.now.iso8601,
      environment: 'test',
      schema: schema || {
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
      },
      models: models,
      routes: { total_routes: routes.values.sum(&:size), by_controller: routes }.merge(route_metadata),
      controllers: { controllers: controllers },
      gems: { notable_gems: [{ name: 'devise', category: 'auth' }] },
      conventions: { architecture: ['mvc'], patterns: ['service_objects'] },
      tests: { framework: 'rspec' }
    }
  end

  let(:large_models) do
    45.times.to_h do |i|
      model("Model#{i}", associations: i % 7, validations: i % 4)
    end.merge(
      [model('Account', tier: 'core_entity', associations: 4, validations: 2)].to_h
    )
  end

  let(:fixtures) do
    {
      standard_crud: base_context(
        models: [model('User', tier: 'core_entity', associations: 3), model('Post', associations: 2)].to_h,
        routes: { 'users' => 7.times.map { {} }, 'posts' => 7.times.map { {} } },
        controllers: { 'UsersController' => { actions: %w[index show] } }
      ),
      large_schema: base_context(
        models: large_models,
        routes: { 'accounts' => 9.times.map { {} }, 'reports' => 4.times.map { {} } }
      ),
      api_only: base_context(
        models: [model('ApiToken', tier: 'core_entity', associations: 1)].to_h,
        routes: { 'api/v1/tokens' => 5.times.map { {} } },
        controllers: { 'Api::V1::TokensController' => { actions: %w[index create] } }
      ),
      hotwire: base_context(
        models: [model('Message', tier: 'core_entity', associations: 2)].to_h,
        routes: { 'messages' => 8.times.map { {} } }
      ).merge(views: { templates: 12, partials: 9 }, stimulus: { controllers: 4 }),
      engine_style: base_context(
        models: [model('Billing::Subscription', tier: 'core_entity', associations: 3)].to_h,
        routes: { 'billing/subscriptions' => 6.times.map { {} } },
        route_metadata: { mounted_engines: [{ engine: 'Billing::Engine', path: '/billing' }] }
      ),
      regulated: base_context(
        models: {},
        schema: { skipped: true, reason: 'domain metadata disabled' },
        routes: { 'health_checks' => 1.times.map { {} } }
      )
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
    output = RailsAiBridge::Serializers::Providers::CodexSerializer.new(fixtures.fetch(:regulated)).call

    expect(output).to include('rails_get_model_details(detail:"summary")')
    expect(output).not_to include('Database:')
    expect(output).not_to include('## Models (')
  end

  it 'serializes large fixture output within a small benchmark budget' do
    elapsed = Benchmark.realtime do
      10.times { RailsAiBridge::Serializers::Providers::CodexSerializer.new(fixtures.fetch(:large_schema)).call }
    end

    expect(elapsed).to be < 0.5
  end
end
