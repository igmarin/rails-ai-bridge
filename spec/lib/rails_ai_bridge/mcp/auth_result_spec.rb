# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::AuthResult do
  describe ".ok" do
    it "marks success with optional context" do
      r = described_class.ok(:ctx)
      expect(r).to be_success
      expect(r).not_to be_failure
      expect(r.context).to eq(:ctx)
      expect(r.error).to be_nil
    end
  end

  describe ".fail" do
    it "marks failure with error key" do
      r = described_class.fail(:missing_token)
      expect(r).not_to be_success
      expect(r).to be_failure
      expect(r.context).to be_nil
      expect(r.error).to eq(:missing_token)
    end
  end
end
