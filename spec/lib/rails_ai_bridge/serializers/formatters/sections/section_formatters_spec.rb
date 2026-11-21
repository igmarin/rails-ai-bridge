# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      RSpec.describe 'Section formatter classes' do
        # :reek:UtilityFunction
        def render(klass, ctx)
          klass.new(ctx).call
        end

        # ---------------------------------------------------------------------------
        # SchemaFormatter
        # ---------------------------------------------------------------------------
        describe SchemaFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { schema: { error: 'x' } })).to be_nil }

          it 'renders schema heading with table count' do
            ctx = { schema: { total_tables: 2,
                              tables: { 'users' => { columns: [{ name: 'id', type: 'integer' }] } } } }
            expect(render(described_class, ctx)).to include('Database Schema')
          end
        end

        # ---------------------------------------------------------------------------
        # ModelsFormatter
        # ---------------------------------------------------------------------------
        describe ModelsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { models: { error: 'x' } })).to be_nil }

          it 'renders models heading with model count' do
            ctx = { models: { 'User' => { associations: [], validations: [] } } }
            expect(render(described_class, ctx)).to include('Models (1)')
          end
        end

        # ---------------------------------------------------------------------------
        # RoutesFormatter
        # ---------------------------------------------------------------------------
        describe RoutesFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { routes: { error: 'x' } })).to be_nil }

          it 'renders routes heading with route count' do
            ctx = { routes: { total_routes: 5, by_controller: {} } }
            expect(render(described_class, ctx)).to include('Routes (5 total)')
          end
        end

        # ---------------------------------------------------------------------------
        # JobsFormatter
        # ---------------------------------------------------------------------------
        describe JobsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { jobs: { error: 'x' } })).to be_nil }

          it 'renders jobs heading with job count' do
            ctx = { jobs: { total_jobs: 3, adapter: 'async', jobs: ['FooJob'] } }
            expect(render(described_class, ctx)).to include('Jobs (3)')
          end
        end

        # ---------------------------------------------------------------------------
        # GemsFormatter
        # ---------------------------------------------------------------------------
        describe GemsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { gems: { error: 'x' } })).to be_nil }

          it 'renders gems heading with gem count' do
            ctx = { gems: { total_gems: 50, notable_gems: [] } }
            expect(render(described_class, ctx)).to include('Total gems: `50`')
          end
        end

        # ---------------------------------------------------------------------------
        # ConventionsFormatter
        # ---------------------------------------------------------------------------
        describe ConventionsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { conventions: { error: 'x' } })).to be_nil }

          it 'renders conventions heading' do
            ctx = { conventions: { architecture: ['hotwire'] } }
            expect(render(described_class, ctx)).to include('App Conventions & Architecture')
          end

          it 'omits secret-bearing config file paths' do
            ctx = {
              conventions: {
                config_files: [
                  'config/database.yml',
                  '.env',
                  'config/credentials.yml.enc',
                  'config/master.key',
                  'config/private.pem'
                ]
              }
            }
            output = render(described_class, ctx)

            expect(output).to include('config/database.yml')
            expect(output).not_to include('.env')
            expect(output).not_to include('credentials.yml.enc')
            expect(output).not_to include('master.key')
            expect(output).not_to include('private.pem')
          end

          it 'returns nil when only secret-bearing config files are present' do
            ctx = { conventions: { config_files: ['.env', 'config/master.key'] } }

            expect(render(described_class, ctx)).to be_nil
          end
        end

        # ---------------------------------------------------------------------------
        # ControllersFormatter
        # ---------------------------------------------------------------------------
        describe ControllersFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { controllers: { error: 'x' } })).to be_nil }

          it 'renders controllers heading with count' do
            ctx = { controllers: { controllers: { 'UsersController' => { actions: [] } } } }
            expect(render(described_class, ctx)).to include('Controllers (1)')
          end
        end

        # ---------------------------------------------------------------------------
        # ViewsFormatter
        # ---------------------------------------------------------------------------
        describe ViewsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { views: { error: 'x' } })).to be_nil }

          it 'renders views heading with layout count' do
            ctx = { views: { layouts: ['application'] } }
            expect(render(described_class, ctx)).to include('Views')
          end
        end

        # ---------------------------------------------------------------------------
        # TurboFormatter
        # ---------------------------------------------------------------------------
        describe TurboFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { turbo: { error: 'x' } })).to be_nil }

          it 'renders turbo heading' do
            ctx = { turbo: { turbo_streams: ['x'], turbo_frames: [], model_broadcasts: [] } }
            expect(render(described_class, ctx)).to include('Hotwire / Turbo')
          end
        end

        # ---------------------------------------------------------------------------
        # ActiveStorageFormatter
        # ---------------------------------------------------------------------------
        describe ActiveStorageFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }

          it('returns nil on error')    {
            expect(render(described_class, { active_storage: { error: 'x' } })).to be_nil
          }

          it 'renders ActiveStorage heading' do
            ctx = { active_storage: { models: ['User'] } }
            expect(render(described_class, ctx)).to include('Active Storage')
          end
        end

        # ---------------------------------------------------------------------------
        # ActionTextFormatter
        # ---------------------------------------------------------------------------
        describe ActionTextFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { action_text: { error: 'x' } })).to be_nil }

          it 'renders ActionText heading' do
            ctx = { action_text: { models: ['Article'] } }
            expect(render(described_class, ctx)).to include('Action Text')
          end
        end

        # ---------------------------------------------------------------------------
        # I18nFormatter
        # ---------------------------------------------------------------------------
        describe I18nFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { i18n: { error: 'x' } })).to be_nil }

          it 'renders I18n heading' do
            ctx = { i18n: { locales: ['en'] } }
            expect(render(described_class, ctx)).to include('Internationalization (I18n)')
          end
        end
      end
    end
  end
end
