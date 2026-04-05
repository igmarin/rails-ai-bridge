# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::Providers::ClaudeRulesSerializer do
  let(:context) do
    {
      schema: {
        adapter: "postgresql",
        tables: {
          "users" => { columns: [ { name: "id" }, { name: "email" } ], primary_key: "id" },
          "posts" => { columns: [ { name: "id" }, { name: "title" } ], primary_key: "id" }
        }
      },
      app_name: "Dummy",
      rails_version: "7.1.0",
      ruby_version: RUBY_VERSION,
      environment: "test",
      models: {
        "User" => { table_name: "users", semantic_tier: "core_entity", associations: [ { type: "has_many", name: "posts" } ], validations: [] },
        "Post" => { table_name: "posts", semantic_tier: "supporting", associations: [ { type: "belongs_to", name: "user" } ], validations: [] }
      }
    }
  end

  it "generates .claude/rules/ files" do
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(4)

      context_file = File.join(dir, ".claude", "rules", "rails-context.md")
      expect(File.exist?(context_file)).to be true
      ctx = File.read(context_file)
      expect(ctx).to include("Rails semantic context")
      expect(ctx).to include("core entity")
      expect(ctx).to include("User")

      schema_file = File.join(dir, ".claude", "rules", "rails-schema.md")
      expect(File.exist?(schema_file)).to be true
      content = File.read(schema_file)
      expect(content).to include("users")
      expect(content).to include("rails_get_schema")

      models_file = File.join(dir, ".claude", "rules", "rails-models.md")
      expect(File.exist?(models_file)).to be true
      content = File.read(models_file)
      expect(content).to include("User")
      expect(content).to include("tier: core_entity")
      expect(content).to include("rails_get_model_details")

      tools_file = File.join(dir, ".claude", "rules", "rails-mcp-tools.md")
      expect(File.exist?(tools_file)).to be true
      content = File.read(tools_file)
      expect(content).to include("MCP Tool Reference")
      expect(content).to include("rails_get_schema")
      expect(content).to include('detail:"summary"')
      expect(content).to include("limit")
      expect(content).to include("offset")
    end
  end

  it "skips unchanged files" do
    Dir.mktmpdir do |dir|
      first = described_class.new(context).call(dir)
      expect(first[:written].size).to eq(4)

      second = described_class.new(context).call(dir)
      expect(second[:written].size).to eq(0)
      expect(second[:skipped].size).to eq(4)
    end
  end

  it "skips schema rule when no tables" do
    context[:schema] = { adapter: "postgresql", tables: {} }
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(3) # context + models + mcp-tools
    end
  end

  it "skips models rule when no models" do
    context[:models] = {}
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].size).to eq(3) # context + schema + mcp-tools
    end
  end
end
