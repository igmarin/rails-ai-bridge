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

  describe "rails-context.md content" do
    it "includes application metadata" do
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("Dummy")
        expect(ctx).to include("7.1.0")
        expect(ctx).to include("test")
      end
    end

    it "groups models by semantic tier with correct headers" do
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("### core entity (1)")
        expect(ctx).to include("### supporting (1)")
        expect(ctx).to include("- User")
        expect(ctx).to include("- Post")
      end
    end

    it "includes model classification guide" do
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("pure_join")
        expect(ctx).to include("rich_join")
        expect(ctx).to include("core_entity")
        expect(ctx).to include("supporting")
      end
    end

    it "includes pointers to other files" do
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("rails-schema.md")
        expect(ctx).to include("rails_get_model_details")
      end
    end

    it "still generates context file even when models have no semantic_tier" do
      context[:models] = {
        "Widget" => { table_name: "widgets", associations: [], validations: [] }
      }
      Dir.mktmpdir do |dir|
        result = described_class.new(context).call(dir)
        context_file = File.join(dir, ".claude", "rules", "rails-context.md")
        expect(File.exist?(context_file)).to be true
        ctx = File.read(context_file)
        # Widget falls back to supporting tier when no semantic_tier present
        expect(ctx).to include("Widget")
      end
    end

    it "skips context file when models hash has an error key" do
      context[:models] = { error: "Something went wrong" }
      Dir.mktmpdir do |dir|
        result = described_class.new(context).call(dir)
        context_file = File.join(dir, ".claude", "rules", "rails-context.md")
        # When models has :error, render_context_reference returns nil → file skipped
        written_names = result[:written].map { |f| File.basename(f) }
        expect(written_names).not_to include("rails-context.md")
      end
    end

    it "omits models with :error from context tier grouping" do
      context[:models] = {
        "GoodModel" => { table_name: "good_models", semantic_tier: "supporting" },
        "BadModel" => { error: "Could not load" }
      }
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("GoodModel")
        expect(ctx).not_to include("BadModel")
      end
    end

    it "renders context without app metadata when metadata fields are absent" do
      context.delete(:app_name)
      context.delete(:rails_version)
      context.delete(:ruby_version)
      context.delete(:environment)
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        ctx = File.read(File.join(dir, ".claude", "rules", "rails-context.md"))
        expect(ctx).to include("# Rails semantic context")
        expect(ctx).not_to include("**Name:**")
        expect(ctx).not_to include("**Rails:**")
      end
    end
  end

  describe "rails-models.md tier annotation" do
    it "annotates each model with its semantic tier" do
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        content = File.read(File.join(dir, ".claude", "rules", "rails-models.md"))
        expect(content).to include("— tier: core_entity")
        expect(content).to include("— tier: supporting")
      end
    end

    it "omits tier annotation when model has no semantic_tier" do
      context[:models] = {
        "Widget" => { table_name: "widgets", associations: [], validations: [] }
      }
      Dir.mktmpdir do |dir|
        described_class.new(context).call(dir)
        content = File.read(File.join(dir, ".claude", "rules", "rails-models.md"))
        expect(content).to include("Widget")
        expect(content).not_to include("— tier:")
      end
    end
  end
end