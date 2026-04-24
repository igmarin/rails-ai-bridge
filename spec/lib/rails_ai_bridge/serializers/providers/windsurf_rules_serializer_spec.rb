# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::WindsurfRulesSerializer do
  let(:context) do
    {
      app_name: 'App', rails_version: '8.0', ruby_version: '3.4',
      schema: { adapter: 'postgresql', total_tables: 10 },
      models: { 'User' => { associations: [] } },
      routes: { total_routes: 50 },
      gems: {}, conventions: {}
    }
  end

  it 'generates .windsurf/rules/*.md files' do
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(2)

      content = File.read(File.join(dir, '.windsurf', 'rules', 'rails-context.md'))
      expect(content).to include('App')
      expect(content.length).to be <= 5800

      tools_content = File.read(File.join(dir, '.windsurf', 'rules', 'rails-mcp-tools.md'))
      expect(tools_content).to include('MCP Tool Reference')
      expect(tools_content).to include('rails_get_schema')
      expect(tools_content.length).to be <= 5800
    end
  end

  it 'enforces character limit on large context' do
    models = 200.times.to_h do |i|
      ["VeryLongModelName#{i}WithExtraText", { associations: [], table_name: "t#{i}" }]
    end
    big_context = context.merge(models: models)

    Dir.mktmpdir do |dir|
      result = described_class.new(big_context).call(dir)
      content = File.read(result[:written].first)
      expect(content.length).to be <= 5800
    end
  end

  it 'skips unchanged files' do
    Dir.mktmpdir do |dir|
      first = described_class.new(context).call(dir)
      second = described_class.new(context).call(dir)
      expect(second[:written]).to be_empty
      expect(second[:skipped].size).to eq(first[:written].size)
    end
  end
end
