# frozen_string_literal: true

require 'spec_helper'

# Branch-coverage specs for tool ResponseFormatter classes that are exercised
# through the public +.call+ interface but have conditional branches not yet
# reached by existing specs.
RSpec.describe 'Tool formatter branch coverage' do
  # ------------------------------------------------------------------
  # GetControllers::ResponseFormatter
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetControllers do
    before { described_class.reset_cache! }

    describe 'uncovered branches' do
      before do
        allow(described_class).to receive(:cached_section).with(:controllers).and_return({
                                                                                           controllers: {
                                                                                             'PostsController' => {
                                                                                               parent_class: 'ApplicationController',
                                                                                               api_controller: true,
                                                                                               actions: %w[index show],
                                                                                               filters: [
                                                                                                 { kind: 'before', name: 'auth', only: ['show'], except: ['index'],
                                                                                                   source: 'ApplicationController' },
                                                                                                 { kind: 'after', name: 'log', source: nil }
                                                                                               ],
                                                                                               strong_params: ['post_params']
                                                                                             },
                                                                                             'BlankController' => {
                                                                                               actions: nil,
                                                                                               filters: nil,
                                                                                               strong_params: nil
                                                                                             },
                                                                                             'ErrorController' => { error: 'load failed' }
                                                                                           }
                                                                                         })
      end

      it 'falls back to name list for unknown detail level' do
        text = described_class.call(detail: 'bogus').content.first[:text]
        expect(text).to include('# Controllers (3)')
        expect(text).to include('- BlankController')
      end

      it 'renders single controller with api_controller flag' do
        text = described_class.call(controller: 'PostsController').content.first[:text]
        expect(text).to include('**API controller:** yes')
      end

      it 'renders single controller with error' do
        text = described_class.call(controller: 'ErrorController').content.first[:text]
        expect(text).to include('Error inspecting ErrorController: load failed')
      end

      it 'renders filter lines with except clause in single controller mode' do
        text = described_class.call(controller: 'PostsController').content.first[:text]
        expect(text).to include('(except: index)')
      end

      it 'renders filter lines with source in full listing mode' do
        text = described_class.call(detail: 'full').content.first[:text]
        expect(text).to include('before auth (ApplicationController)')
      end

      it 'renders full listing with blank controller (no actions/filters/strong_params)' do
        text = described_class.call(detail: 'full').content.first[:text]
        expect(text).to include('## BlankController')
      end

      it 'renders summary with nil actions' do
        text = described_class.call(detail: 'summary').content.first[:text]
        expect(text).to include('**BlankController** — 0 actions')
      end

      it 'renders standard with nil actions as none' do
        text = described_class.call(detail: 'standard').content.first[:text]
        expect(text).to include('**BlankController** — none')
      end
    end
  end

  # ------------------------------------------------------------------
  # GetStimulus::ResponseFormatter
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetStimulus do
    before { described_class.reset_cache! }

    describe 'uncovered branches' do
      before do
        allow(described_class).to receive(:cached_section).with(:stimulus).and_return({
                                                                                        controllers: [
                                                                                          {
                                                                                            name: 'full',
                                                                                            file: 'app/javascript/controllers/full_controller.js',
                                                                                            targets: %w[input output],
                                                                                            values: { 'open' => 'Boolean' },
                                                                                            actions: %w[toggle reset],
                                                                                            outlets: ['modal'],
                                                                                            classes: ['active']
                                                                                          },
                                                                                          {
                                                                                            name: 'bare',
                                                                                            file: nil,
                                                                                            targets: [],
                                                                                            values: nil,
                                                                                            actions: [],
                                                                                            outlets: [],
                                                                                            classes: []
                                                                                          }
                                                                                        ]
                                                                                      })
      end

      it 'renders single controller with outlets and classes' do
        text = described_class.call(controller: 'full').content.first[:text]
        expect(text).to include('## Outlets')
        expect(text).to include('- `modal`')
        expect(text).to include('## Classes')
        expect(text).to include('- `active`')
      end

      it 'renders single controller with no file, targets, actions, values, outlets, or classes' do
        text = described_class.call(controller: 'bare').content.first[:text]
        expect(text).to include('# bare')
        expect(text).not_to include('## Targets')
        expect(text).not_to include('## Actions')
        expect(text).not_to include('## Values')
      end

      it 'renders standard listing with controller that has no values' do
        text = described_class.call(detail: 'standard').content.first[:text]
        bare_section = text.split('## bare').last.split('## full').first
        expect(bare_section).not_to include('Values:')
      end

      it 'renders full listing with controller that has no file' do
        text = described_class.call(detail: 'full').content.first[:text]
        bare_section = text.split('## bare').last.split('## full').first
        expect(bare_section).not_to include('File:')
      end
    end
  end

  # ------------------------------------------------------------------
  # GetView formatters
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetView do
    let(:view_data) do
      {
        layouts: %w[application admin],
        template_engines: %w[erb slim],
        templates: {
          'posts' => %w[index show],
          'users' => %w[index]
        },
        partials: {
          shared: %w[_form _nav],
          per_controller: { 'posts' => %w[_body] }
        },
        helpers: [
          { file: 'app/helpers/posts_helper.rb', methods: %w[format_title] }
        ],
        view_components: ['PostComponent']
      }
    end

    describe 'FullFormatter' do
      it 'renders helpers and view components' do
        formatter = RailsAiBridge::Tools::GetView::FullFormatter.new(context: view_data)
        result = formatter.call
        expect(result).to include('## Helpers')
        expect(result).to include('format_title')
        expect(result).to include('## View Components')
        expect(result).to include('PostComponent')
      end

      it 'returns error when controller filter fails' do
        formatter = RailsAiBridge::Tools::GetView::FullFormatter.new(context: view_data, controller: 'missing')
        result = formatter.call
        expect(result).to include('View introspection failed')
      end
    end

    describe 'SummaryFormatter' do
      it 'renders summary with template and partial counts' do
        formatter = RailsAiBridge::Tools::GetView::SummaryFormatter.new(context: view_data)
        result = formatter.call
        expect(result).to include('# View Summary')
        expect(result).to include('- Layouts: 2')
        expect(result).to include('- Template engines: erb, slim')
        expect(result).to include('- Shared partials: 2')
        expect(result).to include('**posts/** — 2 templates, 1 partials')
        expect(result).to include('**users/** — 1 templates, 0 partials')
      end

      it 'skips templates when partial filter is set without controller' do
        formatter = RailsAiBridge::Tools::GetView::SummaryFormatter.new(context: view_data, partial: 'form')
        result = formatter.call
        expect(result).to include('# Partials matching form')
        expect(result).not_to include('**posts/**')
      end

      it 'returns error when partial filter fails' do
        formatter = RailsAiBridge::Tools::GetView::SummaryFormatter.new(context: view_data, partial: 'nonexistent')
        result = formatter.call
        expect(result).to include('View introspection failed')
      end
    end

    describe 'StandardFormatter' do
      it 'renders layouts, template engines, templates, and partials' do
        formatter = RailsAiBridge::Tools::GetView::StandardFormatter.new(context: view_data)
        result = formatter.call
        expect(result).to include('- Layouts: application, admin')
        expect(result).to include('- Template engines: erb, slim')
        expect(result).to include('## Templates by controller')
        expect(result).to include('`posts/`: index, show')
        expect(result).to include('## Shared Partials')
        expect(result).to include('- `_form`')
        expect(result).to include('## Controller Partials')
        expect(result).to include('`posts/`: _body')
      end

      it 'skips templates when partial filter is set without controller' do
        formatter = RailsAiBridge::Tools::GetView::StandardFormatter.new(context: view_data, partial: 'form')
        result = formatter.call
        expect(result).to include('## Shared Partials')
        expect(result).not_to include('## Templates by controller')
      end

      it 'filters by controller name' do
        formatter = RailsAiBridge::Tools::GetView::StandardFormatter.new(context: view_data, controller: 'posts')
        result = formatter.call
        expect(result).to include('# Views for posts')
        expect(result).to include('`posts/`: index, show')
        expect(result).not_to include('users')
      end

      it 'returns error when controller not found' do
        formatter = RailsAiBridge::Tools::GetView::StandardFormatter.new(context: view_data, controller: 'missing')
        result = formatter.call
        expect(result).to include("Controller views 'missing' not found.")
      end
    end

    describe 'SpecificViewFormatter' do
      it 'renders all optional fields when present' do
        analysis = {
          path: 'app/views/posts/show.html.erb',
          template_engine: 'erb',
          partial: true,
          renders: %w[_form _nav],
          turbo_frames: ['modal'],
          stimulus_controllers: ['clipboard'],
          stimulus_actions: ['copy'],
          content: "<h1>Hello</h1>\n"
        }
        formatter = RailsAiBridge::Tools::GetView::SpecificViewFormatter.new
        result = formatter.call(analysis)
        expect(result).to include('# View: app/views/posts/show.html.erb')
        expect(result).to include('- Template engine: erb')
        expect(result).to include('- Partial: yes')
        expect(result).to include('- Renders: _form, _nav')
        expect(result).to include('- Turbo frames: modal')
        expect(result).to include('- Stimulus controllers: clipboard')
        expect(result).to include('- Stimulus actions: copy')
        expect(result).to include('## Source')
        expect(result).to include('<h1>Hello</h1>')
      end

      it 'renders minimal fields when optional data is absent' do
        analysis = {
          path: 'app/views/posts/index.html.erb',
          template_engine: nil,
          partial: false,
          renders: [],
          turbo_frames: [],
          stimulus_controllers: [],
          stimulus_actions: [],
          content: '<p>Index</p>'
        }
        formatter = RailsAiBridge::Tools::GetView::SpecificViewFormatter.new
        result = formatter.call(analysis)
        expect(result).to include('- Partial: no')
        expect(result).not_to include('Template engine')
        expect(result).not_to include('Renders:')
        expect(result).not_to include('Turbo frames:')
      end
    end
  end

  # ------------------------------------------------------------------
  # GetGems::ResponseFormatter
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::GetGems do
    before { described_class.reset_cache! }

    it 'filters by category' do
      allow(described_class).to receive(:cached_section).with(:gems).and_return({
                                                                                  total_gems: 10,
                                                                                  notable_gems: [
                                                                                    { name: 'devise', version: '4.9', category: 'auth', note: 'Authentication' },
                                                                                    { name: 'sidekiq', version: '7.0', category: 'jobs', note: 'Background jobs' }
                                                                                  ]
                                                                                })
      text = described_class.call(category: 'auth').content.first[:text]
      expect(text).to include('**devise**')
      expect(text).not_to include('**sidekiq**')
    end

    it 'shows no notable gems message for all' do
      allow(described_class).to receive(:cached_section).with(:gems).and_return({
                                                                                  total_gems: 5,
                                                                                  notable_gems: []
                                                                                })
      text = described_class.call.content.first[:text]
      expect(text).to include('_No notable gems found._')
    end

    it 'shows no notable gems message for specific category' do
      allow(described_class).to receive(:cached_section).with(:gems).and_return({
                                                                                  total_gems: 5,
                                                                                  notable_gems: [
                                                                                    { name: 'devise', version: '4.9', category: 'auth', note: 'Authentication' }
                                                                                  ]
                                                                                })
      text = described_class.call(category: 'jobs').content.first[:text]
      expect(text).to include("_No notable gems found in category 'jobs'._")
    end
  end

  # ------------------------------------------------------------------
  # SearchCode::Formatter
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::SearchCode::Formatter do
    it 'formats results with path' do
      formatter = described_class.new
      result = formatter.call([{ file: 'app.rb', line_number: 10, content: '  hello  ' }], 'hello', 'app/')
      expect(result).to include('# Search: `hello`')
      expect(result).to include('**1 results** in app/')
      expect(result).to include('app.rb:10: hello')
    end

    it 'formats no results with path' do
      formatter = described_class.new
      result = formatter.call([], 'missing', 'lib/')
      expect(result).to include("No results found for 'missing' in lib/")
    end

    it 'formats no results without path' do
      formatter = described_class.new
      result = formatter.call([], 'missing', nil)
      expect(result).to include("No results found for 'missing'.")
      expect(result).not_to include('in ')
    end

    it 'formats results without path' do
      formatter = described_class.new
      result = formatter.call([{ file: 'app.rb', line_number: 1, content: 'test' }], 'test', nil)
      expect(result).to include('**1 results**')
      expect(result).not_to include(' in ')
    end
  end

  # ------------------------------------------------------------------
  # Schema formatters
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::Schema::SummaryFormatter do
    it 'shows pagination hint when more tables exist' do
      tables = {
        'a' => { columns: [{ name: 'id', type: 'integer' }], indexes: [{ name: 'idx', columns: ['id'], unique: true }] },
        'b' => { columns: [], indexes: [] },
        'c' => { columns: nil, indexes: nil }
      }
      formatter = described_class.new(tables: tables, total: 3, limit: 1, offset: 0, source: :live)
      result = formatter.call
      expect(result).to include('# Schema Summary (3 tables)')
      expect(result).to include('- **a**')
      expect(result).to include('1 columns, 1 indexes')
      expect(result).to include('Use `offset:1` for more')
    end

    it 'omits pagination hint when all tables shown' do
      tables = { 'a' => { columns: [], indexes: [] } }
      formatter = described_class.new(tables: tables, total: 1, limit: 10, offset: 0)
      result = formatter.call
      expect(result).not_to include('Use `offset:')
    end
  end

  describe RailsAiBridge::Tools::Schema::StandardFormatter do
    it 'renders columns and partition note' do
      tables = {
        'users' => { columns: [{ name: 'id', type: 'integer' }], partition_of: 'parent_table', partition_bound: 'FOR VALUES FROM (1) TO (100)' }
      }
      formatter = described_class.new(tables: tables, total: 1, limit: 10, offset: 0, source: :static)
      result = formatter.call
      expect(result).to include('# Schema (1 tables, showing 1)')
      expect(result).to include('### users')
      expect(result).to include('id:integer')
      expect(result).to include('partition of parent_table (FOR VALUES FROM (1) TO (100))')
    end

    it 'renders partitioned note without partition_by' do
      tables = { 'events' => { columns: [], partitioned: true } }
      formatter = described_class.new(tables: tables, total: 1, limit: 10, offset: 0)
      result = formatter.call
      expect(result).to include('partitioned')
    end

    it 'renders partitioned by note' do
      tables = { 'events' => { columns: [], partitioned: true, partition_by: 'RANGE (created_at)' } }
      formatter = described_class.new(tables: tables, total: 1, limit: 10, offset: 0)
      result = formatter.call
      expect(result).to include('partitioned by RANGE (created_at)')
    end

    it 'shows pagination hint' do
      tables = { 'a' => { columns: [] } }
      formatter = described_class.new(tables: tables, total: 5, limit: 1, offset: 0)
      result = formatter.call
      expect(result).to include('Use `detail:"summary"`')
    end
  end

  describe RailsAiBridge::Tools::Schema::TableFormatter do
    it 'renders columns, indexes, and foreign keys' do
      data = {
        columns: [
          { name: 'id', type: 'integer', null: false, default: nil },
          { name: 'email', type: 'string', null: true, default: "'a@b.c'" }
        ],
        indexes: [{ name: 'idx_email', columns: ['email'], unique: true }],
        foreign_keys: [{ column: 'user_id', to_table: 'users', primary_key: 'id' }]
      }
      formatter = described_class.new(name: 'posts', data: data, source: :live)
      result = formatter.call
      expect(result).to include('## Table: posts')
      expect(result).to include('| id | integer | no | - |')
      expect(result).to include('| email | string | yes | \'a@b.c\' |')
      expect(result).to include('### Indexes')
      expect(result).to include('`idx_email` on (email) (unique)')
      expect(result).to include('### Foreign keys')
      expect(result).to include('`user_id` → `users.id`')
    end

    it 'renders partition_of heading' do
      data = { columns: [], partition_of: 'parent', partition_bound: 'BOUND' }
      formatter = described_class.new(name: 'child', data: data)
      result = formatter.call
      expect(result).to include('_Partition of `parent` — BOUND_')
    end

    it 'renders partitioned heading with partition_by' do
      data = { columns: [], partitioned: true, partition_by: 'RANGE (id)' }
      formatter = described_class.new(name: 'events', data: data)
      result = formatter.call
      expect(result).to include('_Partitioned by RANGE (id)_')
    end

    it 'renders partitioned heading without partition_by' do
      data = { columns: [], partitioned: true }
      formatter = described_class.new(name: 'events', data: data)
      result = formatter.call
      expect(result).to include('_Partitioned_')
    end

    it 'handles nil columns and indexes' do
      data = { columns: nil, indexes: nil, foreign_keys: nil }
      formatter = described_class.new(name: 'empty', data: data)
      result = formatter.call
      expect(result).to include('## Table: empty')
      expect(result).to include('| Column | Type | Nullable | Default |')
    end
  end

  # ------------------------------------------------------------------
  # ModelDetails formatters
  # ------------------------------------------------------------------
  describe RailsAiBridge::Tools::ModelDetails::SummaryFormatter do
    it 'renders model list with semantic tier' do
      models = { 'User' => { semantic_tier: 'core' }, 'Post' => { semantic_tier: nil } }
      formatter = described_class.new(models: models)
      result = formatter.call
      expect(result).to include('# Available models (2)')
      expect(result).to include('- Post')
      expect(result).to include('- User (core)')
    end

    it 'handles non-hash model data' do
      models = { 'Foo' => nil }
      formatter = described_class.new(models: models)
      result = formatter.call
      expect(result).to include('- Foo')
    end

    it 'appends non-AR models' do
      models = { 'User' => {} }
      non_ar = { non_ar_models: [{ name: 'PaymentGateway', relative_path: 'app/models/payment_gateway.rb', tag: 'PORO' }] }
      formatter = described_class.new(models: models, non_ar_models: non_ar)
      result = formatter.call
      expect(result).to include('PaymentGateway')
      expect(result).to include('Non-ActiveRecord classes')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::StandardFormatter do
    it 'renders models with tier and association/validation counts' do
      models = {
        'User' => { associations: [{ type: 'has_many', name: 'posts' }], validations: [{ kind: 'presence', attributes: ['name'] }], semantic_tier: 'core',
                    semantic_tier_reason: 'central entity' },
        'Post' => { associations: [], validations: [], semantic_tier: nil },
        'Error' => { error: 'boom' }
      }
      formatter = described_class.new(models: models)
      result = formatter.call
      expect(result).to include('# Models (3)')
      expect(result).to include('- **Post**')
      expect(result).to include('- **User** — tier: core — 1 associations, 1 validations')
      expect(result).not_to include('Error')
    end

    it 'renders model with zero counts' do
      models = { 'Empty' => { associations: nil, validations: nil } }
      formatter = described_class.new(models: models)
      result = formatter.call
      expect(result).to include('- **Empty**')
      expect(result).not_to include('associations')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::FullFormatter do
    it 'renders models with table, tier, and associations' do
      models = {
        'User' => {
          table_name: 'users',
          semantic_tier: 'core',
          associations: [{ type: 'has_many', name: 'posts', source: :reflection }]
        },
        'Post' => { table_name: nil, associations: [], semantic_tier: nil },
        'Error' => { error: 'boom' }
      }
      formatter = described_class.new(models: models)
      result = formatter.call
      expect(result).to include('# Models (3)')
      expect(result).to include('- **User** (table: users) — tier: core')
      expect(result).to include('has_many :posts')
      expect(result).to include('- **Post**')
      expect(result).not_to include('Error')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::SingleModelFormatter do
    it 'renders full model detail with all sections' do
      data = {
        table_name: 'users',
        semantic_tier: 'core',
        semantic_tier_reason: 'central',
        associations: [
          { type: 'has_many', name: 'posts', source: :reflection },
          { type: 'belongs_to', name: 'account', class_name: 'BillingAccount', through: nil, polymorphic: true, dependent: nil },
          { type: 'has_many', name: 'comments', through: 'post_comments', dependent: :destroy }
        ],
        validations: [
          { kind: 'presence', attributes: ['name'], options: {} },
          { kind: 'uniqueness', attributes: ['email'], options: { scope: 'account_id' } }
        ],
        enums: { status: %w[active inactive] },
        scopes: %w[recent published],
        callbacks: { before_save: %w[normalize_email], after_create: %w[send_welcome] },
        concerns: %w[Trackable Validatable],
        instance_methods: %w[full_name admin? active? reset_password update_last_login generate_token validate_email send_notification archive unarchive restore lock unlock ban
                             unban]
      }
      formatter = described_class.new(name: 'User', data: data)
      result = formatter.call
      expect(result).to include('# User')
      expect(result).to include('**Table:** `users`')
      expect(result).to include('**Semantic tier:** `core`')
      expect(result).to include('**Tier reason:** central')
      expect(result).to include('## Associations')
      expect(result).to include('`belongs_to` **account** (class: BillingAccount) [polymorphic]')
      expect(result).to include('`has_many` **comments** through: post_comments dependent: destroy')
      expect(result).to include('## Validations')
      expect(result).to include('`uniqueness` on email (scope: account_id)')
      expect(result).to include('## Enums')
      expect(result).to include('`status`: active, inactive')
      expect(result).to include('## Scopes')
      expect(result).to include('`recent`')
      expect(result).to include('## Callbacks')
      expect(result).to include('`before_save`: normalize_email')
      expect(result).to include('## Concerns')
      expect(result).to include('Trackable')
      expect(result).to include('## Key instance methods')
    end

    it 'renders source macros with boolean, array, and hash values' do
      data = {
        has_secure_password: true,
        has_many_attached: %w[avatar document],
        normalizes: [{ methods: %w[trim], to: 'email' }]
      }
      formatter = described_class.new(name: 'User', data: data)
      result = formatter.call
      expect(result).to include('## Source macros')
      expect(result).to include('`has_secure_password`')
      expect(result).to include('`has_many_attached`: avatar, document')
      expect(result).to include('`normalizes`: trim → email')
    end

    it 'renders association with class_name matching name (no class annotation)' do
      data = {
        associations: [{ type: 'belongs_to', name: 'post', class_name: 'Post', source: :reflection }]
      }
      formatter = described_class.new(name: 'Comment', data: data)
      result = formatter.call
      expect(result).to include('`belongs_to` **post**')
      expect(result).not_to include('(class: Post)')
    end

    it 'limits instance methods to 15' do
      data = { instance_methods: ('a'..'z').to_a }
      formatter = described_class.new(name: 'Big', data: data)
      result = formatter.call
      expect(result).to include('## Key instance methods')
      method_lines = result.lines.select { |l| l.start_with?('- `') }
      expect(method_lines.size).to eq(15)
    end

    it 'renders minimal model with no optional data' do
      data = {}
      formatter = described_class.new(name: 'Bare', data: data)
      result = formatter.call
      expect(result).to include('# Bare')
      expect(result).not_to include('## Associations')
      expect(result).not_to include('## Source macros')
    end
  end
end
