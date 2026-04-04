# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::SharedAssistantGuidance do
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
        sub = File.join(dir, "config", "rails_ai_bridge")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "overrides.md"), "  # Team rule\n\nKeep this.  \n")

        expect(described_class.read_assistant_overrides).to eq("# Team rule\n\nKeep this.")
      end
    end

    it "returns nil when stub omit-merge line is still present" do
      Dir.mktmpdir do |dir|
        allow(Rails.application).to receive(:root).and_return(Pathname.new(dir))
        sub = File.join(dir, "config", "rails_ai_bridge")
        FileUtils.mkdir_p(sub)
        File.write(File.join(sub, "overrides.md"), "<!-- rails-ai-bridge:omit-merge -->\n\n# Noise\n")

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
        sub = File.join(dir, "config", "rails_ai_bridge")
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

  describe ".compact_engineering_rules_footer_lines" do
    let(:base_ctx) { { tests: { framework: "rspec" } } }

    it "starts with the default rules heading and omits architecture without conventions" do
      lines = described_class.compact_engineering_rules_footer_lines(base_ctx)
      expect(lines.first).to eq("## Rules")
      expect(lines.join("\n")).not_to include("Match Architecture")
    end

    it "includes standard bullets, test command, rubocop, and regeneration trailer" do
      md = described_class.compact_engineering_rules_footer_lines(base_ctx).join("\n")
      expect(md).to include("- **Adhere to Conventions:**")
      expect(md).to include("- **Schema as Source of Truth:**")
      expect(md).to include("Run `bundle exec rspec` and `bundle exec rubocop`")
      expect(md).to include("---")
      expect(md).to include("_This context file is auto-generated. Run `rails ai:bridge` to regenerate._")
    end

    it "appends a Match Architecture bullet when architecture conventions are present" do
      ctx = base_ctx.merge(conventions: { architecture: %w[layered hexagonal] })
      md = described_class.compact_engineering_rules_footer_lines(ctx).join("\n")
      expect(md).to include(
        "- **Match Architecture:** Align with the project's architectural style (layered, hexagonal)."
      )
    end

    it "honors a custom rules_heading keyword" do
      lines = described_class.compact_engineering_rules_footer_lines(base_ctx, rules_heading: "## Custom heading")
      expect(lines.first).to eq("## Custom heading")
    end
  end

  describe ".claude_full_footer_lines" do
    let(:base_ctx) { { tests: { framework: "rspec" } } }

    it "returns markdown lines for the Claude full-mode footer" do
      md = described_class.claude_full_footer_lines(base_ctx).join("\n")
      expect(md).to eq(<<~MD.chomp)
        ## Behavioral Rules

        When working in this codebase:
        - Follow existing patterns and conventions detected above
        - Use the database schema as the source of truth for column names and types
        - Respect existing associations and validations when modifying models
        - Run `bundle exec rspec` after making changes to verify correctness

        ---
        _This context file is auto-generated. Run `rails ai:bridge` to regenerate._
      MD
    end
  end
end
