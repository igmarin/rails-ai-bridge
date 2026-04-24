# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::WindsurfSerializer do
  it 'never exceeds 6000 characters even with 200 models' do
    models = 200.times.to_h do |i|
      ["Model#{i}", { associations: [], validations: [], table_name: "t#{i}" }]
    end
    context = {
      app_name: 'BigApp', rails_version: '8.0', ruby_version: '3.4',
      schema: { adapter: 'postgresql', total_tables: 180 },
      models: models, routes: { total_routes: 1500 },
      gems: { notable: [{ name: 'devise', category: :auth }] },
      conventions: { architecture: ['MVC'] }
    }

    output = described_class.new(context).call
    expect(output.length).to be <= 6000
  end

  it 'includes app name and stack info' do
    context = {
      app_name: 'MyApp', rails_version: '8.0', ruby_version: '3.4',
      schema: { adapter: 'postgresql', total_tables: 10 },
      models: { 'User' => { associations: [] } },
      routes: { total_routes: 50 },
      gems: {}, conventions: {}
    }

    output = described_class.new(context).call
    expect(output).to include('MyApp')
    expect(output).to include('Rails 8.0')
    expect(output).to include('MCP Tools')
  end

  it 'includes model names' do
    context = {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      schema: {}, models: { 'User' => { associations: [] }, 'Post' => { associations: [] } },
      routes: {}, gems: {}, conventions: {}
    }

    output = described_class.new(context).call
    expect(output).to include('User')
    expect(output).to include('Post')
  end

  # A1 — complexity sort
  it 'sorts models by complexity score, not alphabetically' do
    context = {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      schema: {}, routes: {}, gems: {}, conventions: {},
      models: {
        'AardvarkModel' => { associations: [], validations: [], callbacks: [], scopes: [] },
        'ZebraModel' => {
          associations: 10.times.map { |j| { type: 'has_many', name: "rel_#{j}" } },
          validations: 5.times.map { |j| { kind: 'presence', attributes: ["attr_#{j}"] } },
          callbacks: 3.times.map { |j| { name: "cb_#{j}" } },
          scopes: 2.times.map { "scope_#{j}" }
        }
      }
    }

    output = described_class.new(context).call
    zebra_pos    = output.index('ZebraModel')
    aardvark_pos = output.index('AardvarkModel')
    expect(zebra_pos).to be < aardvark_pos, 'expected ZebraModel before AardvarkModel'
  end

  # A2 — dynamic test command
  it 'uses dynamic test command based on framework' do
    context = {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      schema: {}, models: {}, routes: {}, gems: {}, conventions: {},
      tests: { framework: 'minitest' }
    }
    output = described_class.new(context).call
    expect(output).to include('bin/rails test')
  end

  # A4 — column hints
  it 'shows top non-housekeeping columns for key models' do
    context = {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      routes: {}, gems: {}, conventions: {},
      models: { 'User' => { associations: [], validations: [], table_name: 'users' } },
      schema: {
        adapter: 'postgresql', total_tables: 1,
        tables: {
          'users' => {
            columns: [
              { name: 'id', type: 'integer' },
              { name: 'name', type: 'string' },
              { name: 'email', type: 'string' },
              { name: 'created_at', type: 'datetime' }
            ]
          }
        }
      }
    }
    output = described_class.new(context).call
    expect(output).to include('[cols:')
    expect(output).to include('name:string')
    expect(output).not_to include('id:integer')
  end

  # A5 — migration recency
  it 'flags recently migrated models' do
    recent_version = "#{(Time.zone.today - 5).strftime('%Y%m%d')}120000"
    context = {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      schema: {}, routes: {}, gems: {}, conventions: {},
      models: { 'User' => { associations: [], validations: [], table_name: 'users' } },
      migrations: {
        recent: [{ version: recent_version, filename: "#{recent_version}_add_role_to_users.rb" }]
      }
    }
    output = described_class.new(context).call
    expect(output).to include('[recently migrated]')
  end
end
