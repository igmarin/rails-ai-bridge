# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::ContextSummary do
  describe '.test_command' do
    it "returns 'bundle exec rspec' for rspec framework" do
      context = { tests: { framework: 'rspec' } }
      expect(described_class.test_command(context)).to eq('bundle exec rspec')
    end

    it "returns 'bin/rails test' for minitest framework" do
      context = { tests: { framework: 'minitest' } }
      expect(described_class.test_command(context)).to eq('bin/rails test')
    end

    it "returns 'bundle exec rspec' when framework is unknown" do
      context = { tests: { framework: 'unknown' } }
      expect(described_class.test_command(context)).to eq('bundle exec rspec')
    end

    it "returns 'bundle exec rspec' when tests key is missing" do
      expect(described_class.test_command({})).to eq('bundle exec rspec')
    end

    it "returns 'bundle exec rspec' when framework is nil" do
      context = { tests: { framework: nil } }
      expect(described_class.test_command(context)).to eq('bundle exec rspec')
    end

    it "returns 'bundle exec rspec' when framework is an empty string" do
      context = { tests: { framework: '' } }
      expect(described_class.test_command(context)).to eq('bundle exec rspec')
    end

    it "returns 'bundle exec rspec' when framework is whitespace only" do
      context = { tests: { framework: '   ' } }
      expect(described_class.test_command(context)).to eq('bundle exec rspec')
    end
  end

  describe '.model_complexity_score' do
    it 'sums associations, validations, callbacks, and scopes sizes' do
      data = {
        associations: [{}, {}, {}],
        validations: [{}, {}],
        callbacks: [{}],
        scopes: [{}, {}]
      }
      expect(described_class.model_complexity_score(data)).to eq(8)
    end

    it 'returns 0 for an empty model' do
      expect(described_class.model_complexity_score({})).to eq(0)
    end

    it 'preserves insertion order for models with identical scores (stable sort)' do
      models = {
        'AardvarkModel' => { associations: [{}], validations: [], callbacks: [], scopes: [] },
        'BeeModel' => { associations: [{}], validations: [], callbacks: [], scopes: [] }
      }
      sorted = models.sort_by { |_n, d| -described_class.model_complexity_score(d) }.map(&:first)
      expect(sorted).to eq(%w[AardvarkModel BeeModel])
    end

    it 'handles unexpected non-array values via Array() coercion' do
      data = { associations: 'bad_value', validations: nil, callbacks: [], scopes: [] }
      expect { described_class.model_complexity_score(data) }.not_to raise_error
    end
  end

  describe '.model_relevance_score' do
    let(:recent_version) { "#{(Time.zone.today - 5).strftime('%Y%m%d')}120000" }

    it 'prioritizes configured core models over alphabetically earlier supporting models' do
      core = {
        table_name: 'accounts',
        semantic_tier: 'core_entity',
        associations: [],
        validations: []
      }
      supporting = {
        table_name: 'aardvarks',
        semantic_tier: 'supporting',
        associations: 6.times.map { {} },
        validations: []
      }

      expect(described_class.model_relevance_score(core, context: {}))
        .to be > described_class.model_relevance_score(supporting, context: {})
    end

    it 'includes route density and recent migration signals' do
      data = {
        table_name: 'orders',
        associations: [],
        validations: [],
        callbacks: [],
        scopes: []
      }
      context = {
        routes: { by_controller: { 'orders' => 5.times.map { {} } } },
        migrations: {
          recent: [{ version: recent_version, filename: "#{recent_version}_add_status_to_orders.rb" }]
        }
      }

      expect(described_class.model_relevance_score(data, name: 'Order', context: context)).to be >= 9
    end
  end

  describe '.models_by_relevance' do
    it 'returns valid model entries sorted by relevance with stable name tie-breaks' do
      models = {
        'Zebra' => { semantic_tier: 'supporting', associations: [] },
        'Account' => { semantic_tier: 'core_entity', associations: [] },
        'Bee' => { semantic_tier: 'supporting', associations: [] }
      }

      expect(described_class.models_by_relevance(models).map(&:first)).to eq(%w[Account Bee Zebra])
    end
  end

  describe '.top_columns' do
    let(:table_data) do
      {
        columns: [
          { name: 'id', type: 'integer' },
          { name: 'name', type: 'string' },
          { name: 'email', type: 'string' },
          { name: 'role', type: 'integer' },
          { name: 'user_id', type: 'integer' },
          { name: 'created_at', type: 'datetime' },
          { name: 'updated_at', type: 'datetime' }
        ]
      }
    end

    it 'excludes id, created_at, updated_at, and *_id columns' do
      cols = described_class.top_columns(table_data)
      col_names = cols.pluck(:name)
      expect(col_names).not_to include('id', 'created_at', 'updated_at', 'user_id')
    end

    it 'returns at most 3 columns' do
      cols = described_class.top_columns(table_data)
      expect(cols.size).to be <= 3
    end

    it 'includes name and type' do
      cols = described_class.top_columns(table_data)
      expect(cols).to include(hash_including(name: 'name', type: 'string'))
    end

    it 'returns empty array when table_data is nil' do
      expect(described_class.top_columns(nil)).to eq([])
    end

    it 'returns empty array when columns key is missing' do
      expect(described_class.top_columns({})).to eq([])
    end

    it 'ignores malformed columns' do
      cols = described_class.top_columns(
        columns: [
          { name: nil, type: 'string' },
          { type: 'datetime' },
          { name: 'email', type: nil },
          'oops',
          { name: 'name', type: 'string' }
        ]
      )

      expect(cols).to eq([{ name: 'name', type: 'string' }])
    end
  end

  describe '.recently_migrated?' do
    let(:recent_version) { "#{(Time.zone.today - 10).strftime('%Y%m%d')}120000" }
    let(:old_version)    { "#{(Time.zone.today - 60).strftime('%Y%m%d')}120000" }

    it 'returns true when a migration within 30 days touches the table' do
      migrations = {
        recent: [
          { version: recent_version, filename: "#{recent_version}_create_users.rb" }
        ]
      }
      expect(described_class.recently_migrated?('users', migrations)).to be true
    end

    it 'returns false when matching migration is older than 30 days' do
      migrations = {
        recent: [
          { version: old_version, filename: "#{old_version}_create_users.rb" }
        ]
      }
      expect(described_class.recently_migrated?('users', migrations)).to be false
    end

    it 'returns false when no migration references the table name' do
      migrations = {
        recent: [
          { version: recent_version, filename: "#{recent_version}_create_posts.rb" }
        ]
      }
      expect(described_class.recently_migrated?('users', migrations)).to be false
    end

    it 'returns true when a recent migration adds columns to the table' do
      migrations = {
        recent: [
          { version: recent_version, filename: "#{recent_version}_add_name_to_users.rb" }
        ]
      }
      expect(described_class.recently_migrated?('users', migrations)).to be true
    end

    it 'does not match table name substrings in other table names' do
      migrations = {
        recent: [
          { version: recent_version, filename: "#{recent_version}_create_admin_users.rb" }
        ]
      }
      expect(described_class.recently_migrated?('users', migrations)).to be false
    end

    it 'returns false when migrations is nil' do
      expect(described_class.recently_migrated?('users', nil)).to be false
    end

    it 'returns false when recent is empty' do
      expect(described_class.recently_migrated?('users', { recent: [] })).to be false
    end
  end

  describe '.routes_stack_line' do
    it 'uses introspected controller count to match split rule headings' do
      context = {
        routes: { total_routes: 100, error: false, by_controller: 350.times.index_with { [] } },
        controllers: {
          error: false,
          controllers: 341.times.index_with { { actions: %w[index] } }
        }
      }

      line = described_class.routes_stack_line(context)
      expect(line).to include('341 controller classes')
      expect(line).to include('350 names in routing')
    end

    it 'falls back to route targets when controller introspection is missing' do
      context = {
        routes: { total_routes: 12, error: false, by_controller: { 'a' => [], 'b' => [] } }
      }

      line = described_class.routes_stack_line(context)
      expect(line).to eq('- Routes: 12 total — 2 route targets (controller inventory unavailable)')
    end
  end

  describe '.route_focus_lines' do
    it 'surfaces busiest route targets with MCP drill-down guidance' do
      context = {
        routes: {
          by_controller: {
            'profiles' => 7.times.map { |i| { verb: 'GET', action: "show#{i}" } },
            'users' => 3.times.map { |i| { verb: 'POST', action: "create#{i}" } }
          }
        }
      }

      lines = described_class.route_focus_lines(context, limit: 1)
      expect(lines.join("\n")).to include('profiles: 7 routes')
      expect(lines.join("\n")).to include('rails_get_routes(controller:"profiles"')
      expect(lines.join("\n")).not_to include('users: 3 routes')
    end
  end

  describe '.database_size_bucket' do
    it 'buckets approximate row counts into actionable labels' do
      expect(described_class.database_size_bucket(nil)).to be_nil
      expect(described_class.database_size_bucket(0)).to eq('small')
      expect(described_class.database_size_bucket(75_000)).to eq('medium')
      expect(described_class.database_size_bucket(2_000_000)).to eq('large')
      expect(described_class.database_size_bucket(25_000_000)).to eq('hot')
    end
  end
end
