# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::RegenerationFooter do
  describe ".markdown" do
    it "renders the context_file variant" do
      expect(described_class.markdown(command: "rails ai:bridge", variant: :context_file)).to eq(<<~MD)
        ---
        _This context file is auto-generated. Run `rails ai:bridge` to regenerate._
      MD
    end

    it "renders the auto_short variant with a custom command" do
      expect(described_class.markdown(command: "rails ai:bridge:codex", variant: :auto_short)).to eq(<<~MD)
        ---
        _Auto-generated. Run `rails ai:bridge:codex` to regenerate._
      MD
    end
  end

  describe ".message_line" do
    it "raises on unknown variant" do
      expect do
        described_class.message_line(command: "x", variant: :nope)
      end.to raise_error(ArgumentError, /unknown regeneration footer variant/)
    end
  end

  describe ".continuation_lines" do
    it "returns a blank line, rule, and message for chaining after body lines" do
      expect(described_class.continuation_lines(command: "rails ai:bridge", variant: :context_file)).to eq(
        [
          "",
          "---",
          "_This context file is auto-generated. Run `rails ai:bridge` to regenerate._"
        ]
      )
    end
  end
end
