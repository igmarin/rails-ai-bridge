# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::Providers::CursorRulesSerializer do
  let(:context) do
    {
      app_name: "App", rails_version: "8.0", ruby_version: "3.4",
      schema: { adapter: "postgresql", total_tables: 10 },
      models: { "User" => { associations: [], validations: [], table_name: "users" } },
      routes: { total_routes: 50 },
      gems: {},
      conventions: {},
      controllers: { controllers: { "UsersController" => { actions: %w[index show] } } }
    }
  end

  it "generates .cursor/rules/*.mdc files with YAML frontmatter" do
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written]).not_to be_empty

      eng = File.read(File.join(dir, ".cursor", "rules", "rails-engineering.mdc"))
      expect(eng).to include("alwaysApply: true")
      expect(eng).to include("Engineering essentials")
      expect(eng).to include("strong params")

      project_rule = File.read(File.join(dir, ".cursor", "rules", "rails-project.mdc"))
      expect(project_rule).to start_with("---")
      expect(project_rule).to include("alwaysApply: true")
      expect(project_rule).to include("rails-engineering.mdc")
    end
  end

  it "generates models rule with glob" do
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)

      models_rule = File.read(File.join(dir, ".cursor", "rules", "rails-models.mdc"))
      expect(models_rule).to include("app/models/**/*.rb")
      expect(models_rule).to include("alwaysApply: false")
      expect(models_rule).to include("User")
    end
  end

  it "generates controllers rule with glob" do
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)

      ctrl_rule = File.read(File.join(dir, ".cursor", "rules", "rails-controllers.mdc"))
      expect(ctrl_rule).to include("app/controllers/**/*.rb")
      expect(ctrl_rule).to include("UsersController")
    end
  end

  it "skips models rule when no models" do
    context[:models] = {}
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].any? { |f| f.include?("rails-models.mdc") }).to be false
    end
  end

  it "skips controllers rule when no controllers" do
    context[:controllers] = { controllers: {} }
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)
      expect(result[:written].any? { |f| f.include?("rails-controllers.mdc") }).to be false
    end
  end

  it "generates MCP tools rule with alwaysApply" do
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)

      tools_rule = File.read(File.join(dir, ".cursor", "rules", "rails-mcp-tools.mdc"))
      expect(tools_rule).to include("alwaysApply: true")
      expect(tools_rule).to include("MCP Tool Reference")
      expect(tools_rule).to include("rails_get_schema")
      expect(tools_rule).to include('detail:"summary"')
      expect(tools_rule).to include("limit")
    end
  end

  it "skips unchanged files" do
    Dir.mktmpdir do |dir|
      first = described_class.new(context).call(dir)
      second = described_class.new(context).call(dir)
      expect(second[:written]).to be_empty
      expect(second[:skipped].size).to eq(first[:written].size)
    end
  end

  # A1 — complexity sort
  it "sorts models by complexity score, not alphabetically" do
    context[:models] = {
      "AardvarkModel" => { associations: [], validations: [], callbacks: [], scopes: [], table_name: "aardvark_models" },
      "ZebraModel"    => {
        associations: 10.times.map { |j| { type: "has_many", name: "rel_#{j}" } },
        validations:   5.times.map { |j| { kind: "presence", attributes: [ "attr_#{j}" ] } },
        callbacks:     3.times.map { |j| { name: "cb_#{j}" } },
        scopes:        2.times.map { "scope_#{j}" },
        table_name: "zebra_models"
      }
    }

    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      models_rule = File.read(File.join(dir, ".cursor", "rules", "rails-models.mdc"))
      zebra_pos    = models_rule.index("ZebraModel")
      aardvark_pos = models_rule.index("AardvarkModel")
      expect(zebra_pos).to be < aardvark_pos, "expected ZebraModel (high complexity) before AardvarkModel"
    end
  end

  # A2 — dynamic test command
  it "uses dynamic test command from context in project rule" do
    context[:tests] = { framework: "minitest" }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      eng = File.read(File.join(dir, ".cursor", "rules", "rails-engineering.mdc"))
      expect(eng).to include("bin/rails test")
    end
  end

  # A3 — enum display
  it "shows enum names inline in models rule" do
    context[:models] = {
      "Order" => {
        associations: [], validations: [], callbacks: [], scopes: [],
        table_name: "orders",
        enums: { "status" => %w[pending shipped], "priority" => %w[low high] }
      }
    }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      models_rule = File.read(File.join(dir, ".cursor", "rules", "rails-models.mdc"))
      expect(models_rule).to include("[enums: status, priority]")
    end
  end

  # A4 — column hints
  it "shows top non-housekeeping columns in models rule" do
    context[:models] = {
      "User" => { associations: [], validations: [], table_name: "users" }
    }
    context[:schema] = {
      adapter: "postgresql", total_tables: 1,
      tables: {
        "users" => {
          columns: [
            { name: "id", type: "integer" },
            { name: "name", type: "string" },
            { name: "email", type: "string" },
            { name: "created_at", type: "datetime" },
            { name: "updated_at", type: "datetime" }
          ]
        }
      }
    }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      models_rule = File.read(File.join(dir, ".cursor", "rules", "rails-models.mdc"))
      expect(models_rule).to include("[cols:")
      expect(models_rule).to include("name:string")
      expect(models_rule).to include("email:string")
      expect(models_rule).not_to include("id:integer")
      expect(models_rule).not_to include("created_at")
    end
  end

  # A5 — migration recency
  it "flags recently migrated models" do
    recent_version = (Date.today - 5).strftime("%Y%m%d") + "120000"
    context[:models] = {
      "User" => { associations: [], validations: [], table_name: "users" }
    }
    context[:migrations] = {
      recent: [ { version: recent_version, filename: "#{recent_version}_add_role_to_users.rb" } ]
    }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      models_rule = File.read(File.join(dir, ".cursor", "rules", "rails-models.mdc"))
      expect(models_rule).to include("[recently migrated]")
    end
  end

  # A6 — controller actions with HTTP verbs
  it "correctly derives route key for namespaced controllers" do
    context[:controllers] = {
      controllers: { "Admin::UsersController" => { actions: %w[index] } }
    }
    context[:routes] = {
      total_routes: 1,
      by_controller: {
        "admin/users" => [ { verb: "GET", action: "index" } ]
      }
    }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      ctrl_rule = File.read(File.join(dir, ".cursor", "rules", "rails-controllers.mdc"))
      expect(ctrl_rule).to include("GET")
      expect(ctrl_rule).to include("index")
    end
  end

  it "shows controller actions with HTTP verbs in controllers rule" do
    context[:controllers] = {
      controllers: { "UsersController" => { actions: %w[index show create] } }
    }
    context[:routes] = {
      total_routes: 3,
      by_controller: {
        "users" => [
          { verb: "GET",  action: "index" },
          { verb: "GET",  action: "show" },
          { verb: "POST", action: "create" }
        ]
      }
    }
    Dir.mktmpdir do |dir|
      described_class.new(context).call(dir)
      ctrl_rule = File.read(File.join(dir, ".cursor", "rules", "rails-controllers.mdc"))
      expect(ctrl_rule).to include("GET")
      expect(ctrl_rule).to include("index")
      expect(ctrl_rule).to include("POST")
      expect(ctrl_rule).to include("create")
    end
  end
end
