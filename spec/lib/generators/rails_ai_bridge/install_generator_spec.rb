# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "generators/rails_ai_bridge/install/install_generator"

RSpec.describe RailsAiBridge::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], {}, destination_root: destination_root) }

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe "#create_initializer" do
    it "documents the current preset sizes" do
      generator.create_initializer

      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))

      expect(content).to include(":standard  — 10 core introspectors")
      expect(content).to include(":full      — all 27 introspectors")
    end

    it "documents the :regulated preset" do
      generator.create_initializer
      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))
      expect(content).to include(":regulated")
    end

    it "documents excluded_tables" do
      generator.create_initializer
      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))
      expect(content).to include("excluded_tables")
    end

    it "documents disabled_introspection_categories" do
      generator.create_initializer
      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))
      expect(content).to include("disabled_introspection_categories")
    end

    it "documents mcp_token_resolver" do
      generator.create_initializer
      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))
      expect(content).to include("mcp_token_resolver")
    end

    it "documents mcp_jwt_decoder" do
      generator.create_initializer
      content = File.read(File.join(destination_root, "config/initializers/rails_ai_bridge.rb"))
      expect(content).to include("mcp_jwt_decoder")
    end
  end

  describe "#show_instructions" do
    it "includes gemini instructions" do
      original_stdout = $stdout
      $stdout = StringIO.new
      generator.show_instructions
      output = $stdout.string
      $stdout = original_stdout

      expect(output).to include("rails ai:bridge:gemini")
      expect(output).to include("Gemini         → GEMINI.md")
    end
  end

  describe "#generate_context_files" do
    it "reports written and skipped files separately" do
      allow(RailsAiBridge).to receive(:generate_context).and_return({
        written: [ "CLAUDE.md" ],
        skipped: [ ".cursorrules" ]
      })
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with("  Created CLAUDE.md", :green)
      expect(generator).to have_received(:say).with("  Unchanged .cursorrules", :blue)
    end
  end
end
