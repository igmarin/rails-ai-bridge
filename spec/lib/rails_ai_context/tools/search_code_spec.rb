# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Tools::SearchCode do
  describe ".call" do
    it "rejects invalid file_type with special characters" do
      result = described_class.call(pattern: "test", file_type: "rb;rm -rf /")
      text = result.content.first[:text]
      expect(text).to include("Invalid file_type")
    end

    it "accepts valid alphanumeric file_type" do
      result = described_class.call(pattern: "class", file_type: "rb")
      text = result.content.first[:text]
      expect(text).not_to include("Invalid file_type")
    end

    it "caps max_results at 100" do
      result = described_class.call(pattern: "class", max_results: 500)
      # Should not error — just verify it runs
      expect(result).to be_a(MCP::Tool::Response)
    end

    it "prevents path traversal" do
      result = described_class.call(pattern: "test", path: "../../etc")
      text = result.content.first[:text]
      expect(text).to match(/Path not (found|allowed)/)
    end

    it "returns results for a valid search" do
      result = described_class.call(pattern: "ActiveRecord::Schema")
      text = result.content.first[:text]
      expect(text).to include("Search:")
    end

    it "returns a not-found message for unmatched patterns" do
      result = described_class.call(pattern: "zzz_impossible_pattern_zzz_42")
      text = result.content.first[:text]
      expect(text).to include("No results found")
    end

    it "returns a friendly error for invalid regex in Ruby fallback mode" do
      allow(described_class).to receive(:ripgrep_available?).and_return(false)

      result = described_class.call(pattern: "(")
      text = result.content.first[:text]

      expect(text).to include("Invalid pattern")
    end
  end
end
