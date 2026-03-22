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

      expect(content).to include(":standard — 9 core introspectors")
      expect(content).to include(":full     — all 26 introspectors")
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
