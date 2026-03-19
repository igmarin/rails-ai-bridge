# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Serializers::SharedAssistantGuidance do
  describe ".read_assistant_overrides" do
    it "returns nil when overrides file does not exist" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        expect(described_class.read_assistant_overrides).to be_nil
      end
    end

    it "returns trimmed body when overrides file exists" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        sub = File.join(dir, "config", "rails_ai_context")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "overrides.md"), "  # Team rule\n\nKeep this.  \n")

        expect(described_class.read_assistant_overrides).to eq("# Team rule\n\nKeep this.")
      end
    end

    it "returns nil when stub omit-merge line is still present" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        sub = File.join(dir, "config", "rails_ai_context")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "overrides.md"), "<!-- rails-ai-context:omit-merge -->\n\n# Noise\n")

        expect(described_class.read_assistant_overrides).to be_nil
      end
    end
  end

  describe ".repo_specific_guidance_section_lines" do
    it "is empty without overrides" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        expect(described_class.repo_specific_guidance_section_lines).to eq([])
      end
    end

    it "includes heading and body when overrides exist" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        sub = File.join(dir, "config", "rails_ai_context")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "overrides.md"), "Only use read replicas for X.")

        lines = described_class.repo_specific_guidance_section_lines
        expect(lines.first).to eq("## Repo-specific guidance")
        expect(lines).to include("Only use read replicas for X.")
      end
    end
  end

  describe ".performance_security_and_rails_examples_lines" do
    it "includes baseline and Rails pattern examples" do
      lines = described_class.performance_security_and_rails_examples_lines.join("\n")
      expect(lines).to include("Performance & security (baseline)")
      expect(lines).to include("find_each")
    end
  end
end
