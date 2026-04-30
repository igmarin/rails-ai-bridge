# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::CopilotSerializer do
  describe 'compact mode' do
    before { RailsAiBridge.configuration.context_mode = :compact }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it 'generates compact output with MCP tool references' do
      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
        schema: { adapter: 'postgresql', total_tables: 10 },
        models: { 'User' => { associations: [{ type: 'has_many', name: 'posts' }], validations: [] } },
        routes: { total_routes: 50, by_controller: { 'users' => [] } },
        gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include('Copilot Context')
      expect(output).to include('MCP tools')
      expect(output).to include('rails_get_schema')
      expect(output).to include('Performance & security (baseline)')
      expect(output).to include('Engineering rules (read first)')
      expect(output).to include('strong parameters')
      expect(output).to include('N+1')
      expect(output).to include('Rails patterns')
      expect(output).to include('find_each')
      expect(output).to include('Repo-specific constraints')
      expect(output).to include('stub guard')
    end

    it 'includes model associations' do
      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
        models: { 'User' => { associations: [{ type: 'has_many', name: 'posts' }] } },
        schema: {}, routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include('has_many :posts')
    end

    it 'shows top non-housekeeping columns in model lines' do
      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
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
        },
        routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include('[cols:')
      expect(output).to include('name:string')
      expect(output).not_to include('id:integer')
    end

    it 'flags recently migrated models' do
      recent_version = "#{(Time.zone.today - 5).strftime('%Y%m%d')}120000"
      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
        models: { 'User' => { associations: [], validations: [], table_name: 'users' } },
        schema: {}, routes: {}, gems: {}, conventions: {},
        migrations: {
          recent: [{ version: recent_version, filename: "#{recent_version}_add_role_to_users.rb" }]
        }
      }

      output = described_class.new(context).call
      expect(output).to include('[recently migrated]')
    end

    it 'sorts key models by complexity score, not alphabetically' do
      models = {
        'AardvarkModel' => { associations: [], validations: [] },
        'ZebraModel' => {
          associations: 8.times.map { |j| { type: 'has_many', name: "rel_#{j}" } },
          validations: 4.times.map { |j| { kind: 'presence', attributes: ["attr_#{j}"] } }
        }
      }

      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
        schema: {}, models: models, routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output.index('ZebraModel')).to be < output.index('AardvarkModel'),
                                            'expected ZebraModel (high complexity) before AardvarkModel (zero complexity)'
    end
  end

  describe 'full mode' do
    before { RailsAiBridge.configuration.context_mode = :full }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it 'delegates to MarkdownSerializer with Copilot header/footer formatters' do
      context = {
        app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
        generated_at: Time.now.iso8601
      }
      output = described_class.new(context).call
      expect(output).to be_a(String)
      expect(output).to include('Copilot Instructions')
    end
  end
end
