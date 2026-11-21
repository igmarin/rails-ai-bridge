# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      RSpec.describe 'Section formatter classes (part 2)' do
        # :reek:UtilityFunction
        def render(klass, ctx)
          klass.new(ctx).call
        end

        describe ConfigFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { config: { error: 'x' } })).to be_nil }

          it 'renders Config heading' do
            ctx = { config: { cache_store: ':memory_store' } }
            expect(render(described_class, ctx)).to include('Application Configuration')
          end
        end

        # ---------------------------------------------------------------------------
        # AssetsFormatter
        # ---------------------------------------------------------------------------
        describe AssetsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { assets: { error: 'x' } })).to be_nil }

          it 'renders Assets heading' do
            ctx = { assets: { precompiler: 'sprockets' } }
            expect(render(described_class, ctx)).to include('Asset Pipeline')
          end
        end

        # ---------------------------------------------------------------------------
        # AuthFormatter
        # ---------------------------------------------------------------------------
        describe AuthFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { auth: { error: 'x' } })).to be_nil }

          it 'renders Auth heading' do
            ctx = { auth: { strategies: ['devise'] } }
            expect(render(described_class, ctx)).to include('Authentication (AuthN/AuthZ)')
          end
        end

        # ---------------------------------------------------------------------------
        # ApiFormatter
        # ---------------------------------------------------------------------------
        describe ApiFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { api: { error: 'x' } })).to be_nil }

          it 'renders API heading' do
            ctx = {
              api: {
                endpoints: [{ verb: 'GET', path: '/widgets', controller: 'Widgets', action: 'index' }]
              }
            }
            expect(render(described_class, ctx)).to include('API Endpoints')
          end
        end

        # ---------------------------------------------------------------------------
        # TestsFormatter
        # ---------------------------------------------------------------------------
        describe TestsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { tests: { error: 'x' } })).to be_nil }

          it 'renders Tests heading' do
            ctx = { tests: { framework: 'RSpec' } }
            expect(render(described_class, ctx)).to include('Testing')
          end
        end

        # ---------------------------------------------------------------------------
        # RakeTasksFormatter
        # ---------------------------------------------------------------------------
        describe RakeTasksFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { rake_tasks: { error: 'x' } })).to be_nil }

          it 'renders Rake Tasks heading' do
            ctx = { rake_tasks: { tasks: [{ name: 'db:migrate' }] } }
            expect(render(described_class, ctx)).to include('Rake Tasks')
          end
        end

        # ---------------------------------------------------------------------------
        # DevopsFormatter
        # ---------------------------------------------------------------------------
        describe DevopsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { devops: { error: 'x' } })).to be_nil }

          it 'renders Devops heading' do
            ctx = { devops: { ci_cd: ['GitHub Actions'] } }
            expect(render(described_class, ctx)).to include('DevOps & CI/CD')
          end
        end

        # ---------------------------------------------------------------------------
        # ActionMailboxFormatter
        # ---------------------------------------------------------------------------
        describe ActionMailboxFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }

          it('returns nil on error')    {
            expect(render(described_class, { action_mailbox: { error: 'x' } })).to be_nil
          }

          it 'renders Action Mailbox heading' do
            ctx = { action_mailbox: { mailboxes: [{ name: 'InboundMailbox' }] } }
            expect(render(described_class, ctx)).to include('Action Mailbox')
          end
        end

        # ---------------------------------------------------------------------------
        # MigrationsFormatter
        # ---------------------------------------------------------------------------
        describe MigrationsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { migrations: { error: 'x' } })).to be_nil }

          it 'renders Migrations heading' do
            ctx = { migrations: { total: 0 } }
            expect(render(described_class, ctx)).to include('Migrations')
          end
        end

        # ---------------------------------------------------------------------------
        # SeedsFormatter
        # ---------------------------------------------------------------------------
        describe SeedsFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { seeds: { error: 'x' } })).to be_nil }

          it 'renders Seeds heading' do
            ctx = { seeds: {} }
            expect(render(described_class, ctx)).to include('Database Seeds')
          end
        end

        # ---------------------------------------------------------------------------
        # MiddlewareFormatter
        # ---------------------------------------------------------------------------
        describe MiddlewareFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { middleware: { error: 'x' } })).to be_nil }

          it 'renders Middleware heading' do
            ctx = { middleware: { custom_middleware: [] } }
            expect(render(described_class, ctx)).to include('Custom Middleware')
          end
        end

        # ---------------------------------------------------------------------------
        # EnginesFormatter
        # ---------------------------------------------------------------------------
        describe EnginesFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }
          it('returns nil on error')    { expect(render(described_class, { engines: { error: 'x' } })).to be_nil }

          it 'renders Engines heading' do
            ctx = { engines: { mounted: ['MyEngine'] } }
            expect(render(described_class, ctx)).to include('Rails Engines')
          end
        end

        # ---------------------------------------------------------------------------
        # MultiDatabaseFormatter
        # ---------------------------------------------------------------------------
        describe MultiDatabaseFormatter do
          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }

          it('returns nil on error')    {
            expect(render(described_class, { multi_database: { error: 'x' } })).to be_nil
          }

          it 'renders Multi-Database heading' do
            ctx = { multi_database: { multi_db: true, databases: [{ name: 'primary', adapter: 'postgresql' }] } }
            expect(render(described_class, ctx)).to include('Multi-Database')
          end
        end

        describe CodeIntelligenceFormatter do
          let(:present) { { present: true, graph_path: 'graphify-out/graph.json', generated_at: nil } }

          def ctx(codegraph, graphify)
            { code_intelligence: { codegraph: codegraph, graphify: graphify } }
          end

          it('returns nil when absent') { expect(render(described_class, {})).to be_nil }

          it('returns nil on error') do
            expect(render(described_class, { code_intelligence: { error: 'x' } })).to be_nil
          end

          it 'renders heading when both indexes exist' do
            graphify = present.merge(graph_commit: 'a' * 40, head_commit: 'a' * 40, stale: false)
            output = render(described_class, ctx({ present: true }, graphify))
            expect(output).to include('Code Intelligence Indexes')
            expect(output).to include('CodeGraph')
            expect(output).to include('Graphify')
            expect(output).to include('current')
          end

          it 'renders staleness label when stale' do
            graphify = present.merge(graph_commit: 'b' * 40, head_commit: 'a' * 40, stale: true)
            expect(render(described_class, ctx({ present: false }, graphify)))
              .to include('stale (graph predates current HEAD)')
          end

          it 'renders unknown staleness when commits are missing' do
            graphify = present.merge(graph_commit: nil, head_commit: nil, stale: nil)
            expect(render(described_class, ctx({ present: true }, graphify)))
              .to include('unknown (missing commit info)')
          end
        end
      end
    end
  end
end
