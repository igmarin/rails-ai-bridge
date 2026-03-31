# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Config::Output do
  subject(:output) { described_class.new }

  it "defaults output_dir to nil" do
    expect(output.output_dir).to be_nil
  end

  it "defaults context_mode to :compact" do
    expect(output.context_mode).to eq(:compact)
  end

  it "defaults claude_max_lines to 150" do
    expect(output.claude_max_lines).to eq(150)
  end

  it "defaults max_tool_response_chars to 120_000" do
    expect(output.max_tool_response_chars).to eq(120_000)
  end

  it "defaults assistant_overrides_path to nil" do
    expect(output.assistant_overrides_path).to be_nil
  end

  it "defaults copilot_compact_model_list_limit to 5" do
    expect(output.copilot_compact_model_list_limit).to eq(5)
  end

  it "defaults codex_compact_model_list_limit to 3" do
    expect(output.codex_compact_model_list_limit).to eq(3)
  end

  describe "#output_dir_for" do
    it "returns output_dir when set" do
      output.output_dir = "/custom/path"
      app = double(root: Pathname("/app"))
      expect(output.output_dir_for(app)).to eq("/custom/path")
    end

    it "returns app.root.to_s when output_dir is nil" do
      app = double(root: Pathname("/app"))
      expect(output.output_dir_for(app)).to eq("/app")
    end
  end
end
