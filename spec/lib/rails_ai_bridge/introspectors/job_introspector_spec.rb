# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::JobIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "returns jobs array" do
      expect(result[:jobs]).to be_an(Array)
    end

    it "returns mailers array" do
      expect(result[:mailers]).to be_an(Array)
    end

    it "returns channels array" do
      expect(result[:channels]).to be_an(Array)
    end
  end
end
