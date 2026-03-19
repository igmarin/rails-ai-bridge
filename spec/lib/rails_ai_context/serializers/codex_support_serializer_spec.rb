# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Serializers::CodexSupportSerializer do
  let(:context) do
    {
      app_name: "App",
      rails_version: "8.0",
      ruby_version: "3.3.10"
    }
  end

  it "generates a .codex/README.md helper file" do
    Dir.mktmpdir do |dir|
      result = described_class.new(context).call(dir)

      expect(result[:written].size).to eq(1)

      readme = File.read(File.join(dir, ".codex", "README.md"))
      expect(readme).to include("Codex")
      expect(readme).to include("AGENTS.md")
      expect(readme).to include(".mcp.json")
      expect(readme).to include("Team rules")
      expect(readme).to include("overrides.md")
      expect(readme).to include("omit-merge")
    end
  end

  it "skips unchanged files" do
    Dir.mktmpdir do |dir|
      first = described_class.new(context).call(dir)
      second = described_class.new(context).call(dir)

      expect(second[:written]).to be_empty
      expect(second[:skipped].size).to eq(first[:written].size)
    end
  end
end
