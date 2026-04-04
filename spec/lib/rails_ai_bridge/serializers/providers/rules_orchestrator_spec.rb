# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/serializers/shared_assistant_guidance"

RSpec.describe RailsAiBridge::Serializers::Providers::RulesOrchestrator do
  let(:context) do
    {
      app_overview: true,
      app_name: "MyApp",
      rails_version: "7.1.3",
      ruby_version: "3.3.0",
      environment: "development",
      database_adapter: "postgresql",
      gems: { notable_gems: [ { name: "rubocop", version: "1.0", note: "Code style linter" } ] },
      conventions: { architecture: [ "hotwire", "service_objects" ] },
      tests: { framework: "rspec" },
      config: { cache_store: ":memory_store" },
      models: {
        "User" => { associations: [ { type: "has_many", name: "posts" } ], validations: [] },
        "Post" => { associations: [], validations: [ { kind: "presence", attributes: [ "title" ] } ] }
      }
    }
  end
  let(:config) { RailsAiBridge::Configuration.new }
  subject(:orchestrator) { described_class.new(context: context, config: config) }

  before do
    allow(RailsAiBridge::Serializers::SharedAssistantGuidance).to receive(:compact_engineering_rules_lines).and_return([ "Engine rules" ])
    allow(RailsAiBridge::Serializers::SharedAssistantGuidance).to receive(:repo_specific_guidance_section_lines).and_return([ "Repo guidance" ])
    allow(RailsAiBridge::Serializers::SharedAssistantGuidance).to receive(:compact_engineering_rules_footer_lines).and_return([ "Footer" ])
    # Stub the McpToolReferenceFormatter to avoid its internal syntax errors from affecting this test
    allow_any_instance_of(RailsAiBridge::Serializers::Providers::McpToolReferenceFormatter).to receive(:call).and_return("MCP Tool Reference Content")
  end

  describe "#call" do
    it "returns a markdown string" do
      expect(orchestrator.call).to be_a(String)
    end

    it "includes the app name and version in the header" do
      expect(orchestrator.call).to include("# MyApp — Project Rules")
      expect(orchestrator.call).to include("Rails 7.1.3 | Ruby 3.3.0")
    end

    it "includes shared engineering rules" do
      expect(orchestrator.call).to include("Engine rules")
    end

    it "includes repo-specific guidance" do
      expect(orchestrator.call).to include("Repo guidance")
    end

    it "includes the application stack and overview" do
      output = orchestrator.call
      expect(output).to include("## Application Stack & Overview")
      expect(output).to include("- **Name:** `MyApp`")
      expect(output).to include("- **Database:** `postgresql`")
    end

    it "includes notable gems" do
      output = orchestrator.call
      expect(output).to include("## Notable Gems")
      expect(output).to include("- `rubocop` (`1.0`): Code style linter")
    end

    it "includes architecture and conventions" do
      output = orchestrator.call
      expect(output).to include("## Architecture & Conventions")
      expect(output).to include("- Hotwire")
      expect(output).to include("- Service objects")
    end

    it "includes key development considerations" do
      output = orchestrator.call
      expect(output).to include("## Key Development Considerations")
      expect(output).to include("- **Test Framework:** `rspec`")
      expect(output).to include("- **Cache Store:** `:memory_store`")
    end

    it "includes the MCP Tool Reference" do
      expect(orchestrator.call).to include("MCP Tool Reference Content")
    end

    it "includes the shared footer" do
      expect(orchestrator.call).to include("Footer")
    end

    context "when models are present" do
      it "appends a compact models section" do
        output = orchestrator.call
        expect(output).to include("## Models (2 total)")
        expect(output).to include("- User (1 associations)")
        expect(output).to include("- Post (0 associations)")
      end
    end

    context "when models are not present or errored" do
      let(:context) { { app_name: "MyApp", models: { error: "Models error" } } }
      it "does not append a models section" do
        expect(orchestrator.call).not_to include("## Models")
      end
    end

    it "uses literal newline characters for formatting" do
      expect(orchestrator.call).to include("
")
    end
  end
end
