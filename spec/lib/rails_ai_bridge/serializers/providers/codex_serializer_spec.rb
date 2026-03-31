# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::Providers::CodexSerializer do
  describe "compact mode" do
    before { RailsAiBridge.configuration.context_mode = :compact }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it "generates AGENTS.md-friendly guidance with MCP references" do
      context = {
        app_name: "App",
        rails_version: "8.0",
        ruby_version: "3.3.10",
        schema: { adapter: "postgresql", total_tables: 10 },
        models: { "User" => { associations: [ { type: "has_many", name: "posts" } ], validations: [] } },
        routes: { total_routes: 50, by_controller: { "users" => [] } },
        conventions: { architecture: [ "mvc" ], patterns: [ "service_objects" ] }
      }

      output = described_class.new(context).call

      expect(output).to include("Codex")
      expect(output).to include("AGENTS.md")
      expect(output.index("Engineering rules")).to be < output.index("Project overview")
      expect(output).to include("rails_get_schema")
      expect(output).to include('detail:"summary"')
      expect(output).to include("User")
      expect(output).to include("Performance & security (baseline)")
      expect(output).to include("Rails patterns")
      expect(output).to include("find_each")
      expect(output).to include("snapshots")
    end

    it "shows top non-housekeeping columns in model lines" do
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.3.10",
        models: { "User" => { associations: [], validations: [], table_name: "users" } },
        schema: {
          adapter: "postgresql", total_tables: 1,
          tables: {
            "users" => {
              columns: [
                { name: "id", type: "integer" },
                { name: "name", type: "string" },
                { name: "email", type: "string" },
                { name: "created_at", type: "datetime" }
              ]
            }
          }
        },
        routes: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output).to include("[cols:")
      expect(output).to include("name:string")
      expect(output).not_to include("id:integer")
    end

    it "flags recently migrated models" do
      recent_version = (Date.today - 5).strftime("%Y%m%d") + "120000"
      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.3.10",
        models: { "User" => { associations: [], validations: [], table_name: "users" } },
        schema: {}, routes: {}, conventions: {},
        migrations: {
          recent: [ { version: recent_version, filename: "#{recent_version}_add_role_to_users.rb" } ]
        }
      }

      output = described_class.new(context).call
      expect(output).to include("[recently migrated]")
    end

    it "sorts key models by complexity score, not alphabetically" do
      models = {
        "AardvarkModel" => { associations: [], validations: [] },
        "ZebraModel"    => {
          associations: 8.times.map { |j| { type: "has_many", name: "rel_#{j}" } },
          validations:  4.times.map { |j| { kind: "presence", attributes: [ "attr_#{j}" ] } }
        }
      }

      context = {
        app_name: "App", rails_version: "8.0", ruby_version: "3.3.10",
        schema: {}, models: models, routes: {}, conventions: {}
      }

      output = described_class.new(context).call
      expect(output.index("ZebraModel")).to be < output.index("AardvarkModel"),
        "expected ZebraModel (high complexity) before AardvarkModel (zero complexity)"
    end
  end

  describe "full mode" do
    before { RailsAiBridge.configuration.context_mode = :full }
    after { RailsAiBridge.configuration.context_mode = :compact }

    it "delegates to a full serializer variant" do
      context = {
        app_name: "App",
        rails_version: "8.0",
        ruby_version: "3.3.10",
        generated_at: Time.now.iso8601
      }

      output = described_class.new(context).call
      expect(output).to be_a(String)
      expect(output).to include("Codex Instructions")
    end
  end
end
