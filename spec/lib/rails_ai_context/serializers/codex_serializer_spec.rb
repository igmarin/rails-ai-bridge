# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Serializers::CodexSerializer do
  describe "compact mode" do
    before { RailsAiContext.configuration.context_mode = :compact }
    after { RailsAiContext.configuration.context_mode = :compact }

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
  end

  describe "full mode" do
    before { RailsAiContext.configuration.context_mode = :full }
    after { RailsAiContext.configuration.context_mode = :compact }

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
