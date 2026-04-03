# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rails_ai_bridge rake tasks" do
  let(:rake) { Rake.application }
  let(:task_path) { File.expand_path("../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake", __dir__) }
  let(:result) { { written: [], skipped: [] } }
  let(:original_context_mode) { RailsAiBridge.configuration.context_mode }

  before(:context) do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake", __dir__)
  end

  before(:each) do
    rake.tasks.each(&:reenable)
    allow(RailsAiBridge).to receive(:generate_context).and_return(result)
  end

  after(:context) do
    Rake.application = @original_rake_application
  end

  after(:each) do
    RailsAiBridge.configuration.context_mode = original_context_mode
  end

  describe "ai:bridge" do
    it "calls generate_context with the :all format" do
      rake["ai:bridge"].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
    end

    it "prints written and skipped files" do
      result[:written] = [ "/foo/CLAUDE.md" ]
      result[:skipped] = [ "/foo/.cursorrules" ]
      original_stdout = $stdout
      $stdout = StringIO.new
      rake["ai:bridge"].invoke
      output = $stdout.string
      $stdout = original_stdout

      expect(output).to include("✅ /foo/CLAUDE.md")
      expect(output).to include("⏭️  /foo/.cursorrules (unchanged)")
    end
  end

  describe "ai:bridge_for" do
    it "calls generate_context with the specified format" do
      rake["ai:bridge_for"].invoke("cursor")
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :cursor)
    end

    it "calls generate_context with format from ENV" do
      ENV["FORMAT"] = "codex"
      rake["ai:bridge_for"].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :codex)
    end

    it "defaults to claude when no format is specified" do
      ENV.delete("FORMAT") # Ensure no ENV variable is interfering
      rake["ai:bridge_for"].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :claude)
    end
  end

  describe "ai:bridge:full" do
    it "sets context_mode to :full and calls generate_context with :all" do
      rake["ai:bridge:full"].invoke
      expect(RailsAiBridge.configuration.context_mode).to eq(:full)
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
    end
  end

  describe "ai:serve" do
    it "starts the MCP server with stdio transport" do
      expect(RailsAiBridge).to receive(:start_mcp_server).with(transport: :stdio)
      rake["ai:serve"].invoke
    end
  end

  describe "ai:serve_http" do
    it "starts the MCP server with http transport" do
      expect(RailsAiBridge).to receive(:start_mcp_server).with(transport: :http)
      rake["ai:serve_http"].invoke
    end
  end

  describe "ai:inspect" do
    it "prints introspection summary to stdout" do
      allow(RailsAiBridge).to receive(:introspect).and_return({
        app_name: "TestApp",
        rails_version: "7.1.3",
        ruby_version: "3.3.0",
        schema: { adapter: "postgresql", total_tables: 5 },
        models: { "User" => {}, "Post" => {} },
        routes: { total_routes: 10 },
        jobs: { jobs: [], mailers: [] },
        conventions: { architecture: [ "Service Objects" ] }
      })

      original_stdout = $stdout
      $stdout = StringIO.new
      rake["ai:inspect"].invoke
      output = $stdout.string
      $stdout = original_stdout

      expect(output).to include("TestApp — AI Context Summary")
      expect(output).to include("Rails 7.1.3 | Ruby 3.3.0")
      expect(output).to include("📦 Database: 5 tables (postgresql)")
      expect(output).to include("🏗️  Models: 2")
      expect(output).to include("🛤️  Routes: 10")
      expect(output).to include("🏛️  Architecture: Service Objects")
    end

    it "handles introspection errors gracefully" do
      allow(RailsAiBridge).to receive(:introspect).and_return({
        app_name: "TestApp",
        rails_version: "7.1.3",
        ruby_version: "3.3.0",
        schema: { error: "DB connection failed" }
      })
      original_stdout = $stdout
      $stdout = StringIO.new
      rake["ai:inspect"].invoke
      output = $stdout.string
      $stdout = original_stdout

      expect(output).to include("TestApp — AI Context Summary")
      expect(output).not_to include("📦 Database")
    end
  end

  describe "ai:doctor" do
    it "runs diagnostic checks" do
      doctor_result = { score: 100, checks: [ double(name: "Check1", message: "OK", status: :pass, fix: nil) ] }
      expect(RailsAiBridge::Doctor).to receive_message_chain(:new, :run).and_return(doctor_result)

      original_stdout = $stdout
      $stdout = StringIO.new
      rake["ai:doctor"].invoke
      output = $stdout.string
      $stdout = original_stdout

      expect(output).to include("🩺 Running AI readiness diagnostics...")
      expect(output).to include("✅ Check1: OK")
      expect(output).to include("AI Readiness Score: 100/100")
    end
  end

  # New test for gemini
  describe "ai:bridge:gemini" do
    it "calls generate_context with the :gemini format" do
      rake["ai:bridge:gemini"].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :gemini)
    end
  end
end
