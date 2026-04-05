# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::NonArModelsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    it "returns a list including plain Ruby classes under app/models" do
      result = introspector.call
      expect(result).not_to have_key(:error)
      names = (result[:non_ar_models] || []).map { |h| h[:name] }
      expect(names).to include("OrderCalculator")
    end

    it "tags entries as POJO/Service" do
      result = introspector.call
      row = result[:non_ar_models].find { |h| h[:name] == "OrderCalculator" }
      expect(row[:tag]).to eq("POJO/Service")
      expect(row[:relative_path]).to eq("app/models/order_calculator.rb")
    end
  end
end
