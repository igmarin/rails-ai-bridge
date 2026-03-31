# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::MarkdownSerializer do
  let(:context) { RailsAiBridge.introspect }

  describe "#call" do
    subject(:output) { described_class.new(context).call }

    it "returns a markdown string" do
      expect(output).to be_a(String)
      expect(output).to include("# ")
    end

    it "includes the app overview" do
      expect(output).to include("## Overview")
    end

    it "includes database schema section" do
      expect(output).to include("## Database Schema")
    end

    it "includes routes section" do
      expect(output).to include("## Routes")
    end

    it "includes the footer" do
      expect(output).to include("rails ai:bridge")
    end

    it "sections are separated by double newlines" do
      expect(output).to include("\n\n##")
    end

    it "includes models section" do
      expect(output).to include("## Models")
    end

    it "does not include nil sections (compact join)" do
      expect(output).not_to include("\n\n\n\n")
    end
  end
end

RSpec.describe RailsAiBridge::Serializers::ClaudeSerializer do
  let(:context) { RailsAiBridge.introspect }

  describe "#call" do
    subject(:output) { described_class.new(context).call }

    context "in compact mode (default)" do
      around do |example|
        original_context_mode = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :compact
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = original_context_mode
      end

      it "includes AI Context header" do
        expect(output).to include("AI Context")
      end

      it "includes MCP tools section" do
        expect(output).to include("MCP tools")
      end

      it "includes rules section" do
        expect(output).to include("## Rules")
      end
    end

    context "in full mode" do
      around do |example|
        original_context_mode = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :full
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = original_context_mode
      end

      it "includes Claude-specific header" do
        expect(output).to include("Claude Code")
      end

      it "includes behavioral rules section" do
        expect(output).to include("## Behavioral Rules")
      end
    end
  end
end

RSpec.describe RailsAiBridge::Serializers::RulesSerializer do
  let(:context) { RailsAiBridge.introspect }

  describe "#call" do
    subject(:output) { described_class.new(context).call }

    it "uses compact project rules header" do
      expect(output).to include("Project Rules")
    end
  end
end

RSpec.describe RailsAiBridge::Serializers::CopilotSerializer do
  let(:context) { RailsAiBridge.introspect }

  describe "#call" do
    subject(:output) { described_class.new(context).call }

    context "in compact mode (default)" do
      around do |example|
        original_context_mode = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :compact
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = original_context_mode
      end

      it "uses Copilot-specific header" do
        expect(output).to include("Copilot Context")
      end
    end

    context "in full mode" do
      around do |example|
        original_context_mode = RailsAiBridge.configuration.context_mode
        RailsAiBridge.configuration.context_mode = :full
        example.run
      ensure
        RailsAiBridge.configuration.context_mode = original_context_mode
      end

      it "uses Copilot Instructions header" do
        expect(output).to include("Copilot Instructions")
      end
    end
  end
end
