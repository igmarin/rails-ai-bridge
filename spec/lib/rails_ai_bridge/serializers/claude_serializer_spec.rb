# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::ClaudeSerializer do
  describe "compact mode" do
    before { RailsAiBridge.configuration.context_mode = :compact }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it "generates ≤150 lines for a large app" do
      models = 200.times.each_with_object({}) do |i, h|
        h["Model#{i}"] = {
          associations: 5.times.map { |j| { type: "has_many", name: "rel_#{j}" } },
          validations: 3.times.map { |j| { kind: "presence", attributes: [ "attr_#{j}" ] } },
          table_name: "model_#{i}s"
        }
      end

      context = {
        app_name: "BigApp", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601,
        schema: { adapter: "postgresql", tables: {}, total_tables: 180 },
        models: models,
        routes: { total_routes: 1500, by_controller: {} },
        gems: { notable: [ { name: "devise", category: :auth } ] },
        conventions: { architecture: [ "MVC", "Service objects" ], patterns: [], config_files: [] },
        jobs: { jobs: [], mailers: [], channels: [] },
        auth: { authentication: {}, authorization: {} },
        migrations: { total: 500, pending: [] }
      }

      output = described_class.new(context).call
      line_count = output.lines.count

      expect(line_count).to be <= 150
      expect(output).to include("MCP tools")
      expect(output).to include("rails_get_schema")
      expect(output).to include('detail:"summary"')
    end

    it "includes key models capped at 15" do
      models = 30.times.each_with_object({}) do |i, h|
        h["Model#{i.to_s.rjust(2, '0')}"] = { associations: [], validations: [] }
      end

      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601, schema: {}, models: models,
        routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include("...15 more")
    end

    it "sorts key models by complexity score (associations + validations + callbacks + scopes), not alphabetically" do
      models = {
        "AardvarkModel" => { associations: [], validations: [], callbacks: [], scopes: [] },
        "ZebraModel"    => {
          associations: 10.times.map { |j| { type: "has_many", name: "rel_#{j}" } },
          validations:  5.times.map  { |j| { kind: "presence", attributes: [ "attr_#{j}" ] } },
          callbacks:    3.times.map  { |j| { name: "cb_#{j}" } },
          scopes:       2.times.map  { |j| "scope_#{j}" }
        }
      }

      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601, schema: {}, models: models,
        routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      zebra_pos    = output.index("ZebraModel")
      aardvark_pos = output.index("AardvarkModel")

      expect(zebra_pos).to be < aardvark_pos, "expected ZebraModel (high complexity) before AardvarkModel (zero complexity)"
    end

    it "shows enum names inline in key model lines using exact format" do
      models = {
        "Order" => {
          associations: [],
          validations: [],
          enums: { "status" => %w[pending shipped delivered], "priority" => %w[low high] }
        }
      }

      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601, schema: {}, models: models,
        routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include("[enums: status, priority]")
    end

    it "uses the dynamic test command based on framework" do
      models = {}
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601, schema: {}, models: models,
        routes: {}, gems: {}, conventions: {},
        tests: { framework: "minitest" }
      }

      output = described_class.new(context).call
      expect(output).to include("bin/rails test")
      expect(output).not_to include("bundle exec rspec")
    end

    it "shows top non-housekeeping columns in key model lines" do
      models = {
        "User" => {
          associations: [], validations: [], table_name: "users"
        }
      }
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601,
        models: models,
        schema: {
          adapter: "postgresql", total_tables: 1,
          tables: {
            "users" => {
              columns: [
                { name: "id", type: "integer" },
                { name: "name", type: "string" },
                { name: "email", type: "string" },
                { name: "role", type: "integer" },
                { name: "created_at", type: "datetime" },
                { name: "updated_at", type: "datetime" }
              ]
            }
          }
        },
        routes: {}, gems: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include("[cols:")
      expect(output).to include("name:string")
      expect(output).to include("email:string")
      expect(output).not_to include("id:integer")
      expect(output).not_to include("created_at")
    end

    it "flags recently migrated models" do
      recent_version = (Date.today - 5).strftime("%Y%m%d") + "120000"
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601,
        models: { "User" => { associations: [], validations: [], table_name: "users" } },
        schema: {}, routes: {}, gems: {}, conventions: {},
        migrations: {
          total: 1, pending: [],
          recent: [ { version: recent_version, filename: "#{recent_version}_add_role_to_users.rb" } ]
        }
      }

      output = described_class.new(context).call
      expect(output).to include("[recently migrated]")
    end

    it "includes app name and version" do
      context = {
        app_name: "MyApp", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601
      }
      output = described_class.new(context).call
      expect(output).to include("MyApp")
      expect(output).to include("Rails 8.0")
    end
  end

  describe "cross-serializer consistency (minitest)" do
    before { RailsAiBridge.configuration.context_mode = :compact }
    after  { RailsAiBridge.configuration.context_mode = :compact }

    let(:minitest_context) do
      {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601, schema: {}, models: {},
        routes: {}, gems: {}, conventions: {},
        tests: { framework: "minitest" }
      }
    end

    it "all three compact serializers use bin/rails test for minitest apps" do
      claude   = RailsAiBridge::Serializers::ClaudeSerializer.new(minitest_context).call
      codex    = RailsAiBridge::Serializers::CodexSerializer.new(minitest_context).call
      copilot  = RailsAiBridge::Serializers::CopilotSerializer.new(minitest_context).call

      aggregate_failures do
        expect(claude).to  include("bin/rails test"), "ClaudeSerializer should use bin/rails test"
        expect(codex).to   include("bin/rails test"), "CodexSerializer should use bin/rails test"
        expect(copilot).to include("bin/rails test"), "CopilotSerializer should use bin/rails test"
      end
    end
  end

  describe "full mode" do
    before { RailsAiBridge.configuration.context_mode = :full }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it "delegates to FullClaudeSerializer (MarkdownSerializer)" do
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.4",
        generated_at: Time.now.iso8601
      }
      output = described_class.new(context).call
      expect(output).to be_a(String)
      expect(output).to include("Claude Code")
    end
  end
end
