# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::ClaudeRulesSerializer do
  let(:context) do
    {
      schema: {
        adapter: 'postgresql',
        tables: {
          'users' => { columns: [{ name: 'id' }, { name: 'email' }], primary_key: 'id' },
          'posts' => { columns: [{ name: 'id' }, { name: 'title' }], primary_key: 'id' }
        }
      },
      app_name: 'Dummy',
      rails_version: '7.1.0',
      ruby_version: RUBY_VERSION,
      environment: 'test',
      models: {
        'User' => { table_name: 'users', semantic_tier: 'core_entity',
                    associations: [{ type: 'has_many', name: 'posts' }], validations: [] },
        'Post' => { table_name: 'posts', semantic_tier: 'supporting',
                    associations: [{ type: 'belongs_to', name: 'user' }], validations: [] }
      },
      routes: {
        total_routes: 7,
        by_controller: { 'users' => 7.times.map { { verb: 'GET', action: 'index' } } }
      },
      non_ar_models: {
        non_ar_models: [
          { name: 'OrderCalculator', relative_path: 'app/models/order_calculator.rb', tag: 'POJO/Service' }
        ]
      }
    }
  end

  it 'generates .claude/rules/ files' do
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(4)

      context_file = File.join(dir, '.claude', 'rules', 'rails-context.md')
      expect(File.exist?(context_file)).to be true
      ctx = File.read(context_file)
      expect(ctx).to include('Rails semantic context')
      expect(ctx).to include('core entity')
      expect(ctx).to include('User')
      expect(ctx).to include('Endpoint focus')
      expect(ctx).to include('rails_get_routes(detail:"summary")')

      schema_file = File.join(dir, '.claude', 'rules', 'rails-schema.md')
      expect(File.exist?(schema_file)).to be true
      content = File.read(schema_file)
      expect(content).to include('users')
      expect(content).to include('rails_get_schema')

      models_file = File.join(dir, '.claude', 'rules', 'rails-models.md')
      expect(File.exist?(models_file)).to be true
      content = File.read(models_file)
      expect(content).to include('User')
      expect(content).to include('tier: core_entity')
      expect(content).to include('rails_get_model_details')
      expect(content).to include('OrderCalculator')
      expect(content).to include('POJO/Service')

      tools_file = File.join(dir, '.claude', 'rules', 'rails-mcp-tools.md')
      expect(File.exist?(tools_file)).to be true
      content = File.read(tools_file)
      expect(content).to include('MCP Tool Reference')
      expect(content).to include('rails_get_schema')
      expect(content).to include('detail:"summary"')
      expect(content).to include('limit')
      expect(content).to include('offset')
    end
  end

  it 'skips unchanged files' do
    Dir.mktmpdir do |dir|
      first = described_class.new(context).call(dir)
      expect(first[:written].size).to eq(4)

      second = described_class.new(context).call(dir)
      expect(second[:written].size).to eq(0)
      expect(second[:skipped].size).to eq(4)
    end
  end

  it 'skips schema rule when no tables' do
    context[:schema] = { adapter: 'postgresql', tables: {} }
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(3) # context + models + mcp-tools
    end
  end

  it 'skips models rule when there are no AR models and no non-AR rows' do
    context[:models] = {}
    context[:non_ar_models] = { non_ar_models: [] }
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(3) # context + schema + mcp-tools
    end
  end

  it 'writes rails-models.md with only non-AR classes when the models hash is empty' do
    context[:models] = {}
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(4)

      models_file = File.join(dir, '.claude', 'rules', 'rails-models.md')
      body = File.read(models_file)
      expect(body).to include('# ActiveRecord Models (0)')
      expect(body).to include('OrderCalculator')
      expect(body).to include('## Non-ActiveRecord classes (POJO/Service)')
    end
  end

  describe 'rails-models.md non-ActiveRecord section' do
    let(:many_non_ar) do
      (1..21).map do |i|
        { name: "Service#{i}", relative_path: "app/models/service#{i}.rb", tag: 'POJO/Service' }
      end
    end

    let(:heavy_non_ar_context) do
      context.merge(non_ar_models: { non_ar_models: many_non_ar })
    end

    # :reek:UtilityFunction
    def non_ar_bullet_lines(body)
      body.lines.grep(%r{\A- \*\*\[POJO/Service\]\*\*})
    end

    it 'caps non-AR rows in compact context_mode with the same overflow hint as tier lists' do
      previous_mode = RailsAiBridge.configuration.context_mode
      RailsAiBridge.configuration.context_mode = :compact
      Dir.mktmpdir do |dir|
        described_class.new(heavy_non_ar_context).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-models.md'))
        expect(non_ar_bullet_lines(body).size).to eq(described_class::SEMANTIC_TIER_LIST_CAP)
        expect(body).to include('+1 more')
        expect(body).to include('rails_get_model_details(detail:"summary")')
      end
    ensure
      RailsAiBridge.configuration.context_mode = previous_mode
    end

    context 'when context_mode is :full' do
      around do |example|
        previous = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :full
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = previous
      end

      it 'lists every non-AR row without overflow' do
        Dir.mktmpdir do |dir|
          described_class.new(heavy_non_ar_context).call(dir)
          body = File.read(File.join(dir, '.claude', 'rules', 'rails-models.md'))
          expect(non_ar_bullet_lines(body).size).to eq(21)
          expect(body).not_to include('+1 more')
        end
      end
    end
  end

  describe 'rails-context.md semantic tier lists' do
    let(:twenty_one_supporting) do
      (1..21).to_h do |i|
        ["M#{i}", { semantic_tier: 'supporting', associations: [], validations: [] }]
      end
    end

    let(:bulky_context) do
      context.merge(models: twenty_one_supporting)
    end

    it 'caps names per tier in compact mode with an MCP overflow hint' do
      previous_mode = RailsAiBridge.configuration.context_mode
      RailsAiBridge.configuration.context_mode = :compact
      Dir.mktmpdir do |dir|
        described_class.new(bulky_context).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-context.md'))
        listed = body.lines.count { |l| l.match?(/\A- M\d+\s*\z/) }
        expect(listed).to eq(described_class::SEMANTIC_TIER_LIST_CAP)
        expect(body).to include('+1 more')
        expect(body).to include('rails_get_model_details')
      end
    ensure
      RailsAiBridge.configuration.context_mode = previous_mode
    end

    context 'when context_mode is :full' do
      around do |example|
        previous = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :full
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = previous
      end

      it 'lists every model in each tier without overflow' do
        Dir.mktmpdir do |dir|
          described_class.new(bulky_context).call(dir)
          body = File.read(File.join(dir, '.claude', 'rules', 'rails-context.md'))
          listed = body.lines.count { |l| l.match?(/\A- M\d+\s*\z/) }
          expect(listed).to eq(21)
          expect(body).not_to include('+1 more')
        end
      end
    end
  end

  describe 'relevance ordering and database size hints' do
    let(:context_with_signals) do
      context.merge(
        routes: {
          total_routes: 18,
          by_controller: {
            'profiles' => 9.times.map { { verb: 'GET', action: 'show' } },
            'users' => 2.times.map { { verb: 'GET', action: 'index' } }
          }
        },
        database_stats: {
          adapter: 'postgresql',
          tables: [
            { table: 'users', approximate_rows: 25_000_000 },
            { table: 'posts', approximate_rows: 12 }
          ]
        },
        models: {
          'Aardvark' => { table_name: 'aardvarks', semantic_tier: 'supporting', associations: [], validations: [] },
          'Profile' => {
            table_name: 'profiles',
            semantic_tier: 'core_entity',
            associations: [{ type: 'belongs_to', name: 'user' }],
            validations: []
          },
          'User' => { table_name: 'users', semantic_tier: 'supporting', associations: [], validations: [] }
        },
        schema: {
          adapter: 'postgresql',
          tables: {
            'users' => { columns: [{ name: 'id' }], primary_key: 'id' },
            'profiles' => { columns: [{ name: 'id' }], primary_key: 'id' },
            'aardvarks' => { columns: [{ name: 'id' }], primary_key: 'id' }
          }
        }
      )
    end

    it 'orders semantic context by task relevance within tiers' do
      Dir.mktmpdir do |dir|
        described_class.new(context_with_signals).call(dir)
        body = File.read(File.join(dir, '.claude', 'rules', 'rails-context.md'))
        expect(body.index('- Profile')).to be < body.index('- Aardvark')
      end
    end

    it 'adds bounded route focus and database size hints' do
      Dir.mktmpdir do |dir|
        described_class.new(context_with_signals).call(dir)
        context_body = File.read(File.join(dir, '.claude', 'rules', 'rails-context.md'))
        schema_body = File.read(File.join(dir, '.claude', 'rules', 'rails-schema.md'))

        expect(context_body).to include('profiles: 9 routes')
        expect(context_body).to include('rails_get_routes(controller:"profiles"')
        expect(schema_body).to include('users (1 cols, pk: id) [hot]')
      end
    end
  end
end
