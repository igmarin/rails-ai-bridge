# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::NonArModelsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    context "when app/models contains non-ActiveRecord classes" do
      it "returns a list including plain Ruby classes under app/models" do
        result = introspector.call
        expect(result).not_to have_key(:error)
        names = (result[:non_ar_models] || []).map { |h| h[:name] }
        expect(names).to include("OrderCalculator")
      end

      it "tags entries as POJO/Service with correct structure" do
        result = introspector.call
        row = result[:non_ar_models].find { |h| h[:name] == "OrderCalculator" }
        expect(row[:tag]).to eq("POJO/Service")
        expect(row[:relative_path]).to eq("app/models/order_calculator.rb")
        expect(row).to have_key(:name)
      end

      it "returns entries sorted by name" do
        result = introspector.call
        entries = result[:non_ar_models]
        names = entries.map { |h| h[:name] }
        expect(names).to eq(names.sort)
      end
    end

    context "when app/models directory does not exist" do
      before do
        allow(Dir).to receive(:exist?).with(introspector.instance_variable_get(:@root) + "/app/models").and_return(false)
      end

      it "returns empty non_ar_models array" do
        result = introspector.call
        expect(result).to eq({ non_ar_models: [] })
      end
    end

    context "when eager loading fails" do
      before do
        # Mock the eager_load! method to raise an error
        allow(introspector).to receive(:eager_load!).and_raise(StandardError.new("Load failed"))
      end

      it "handles errors gracefully and returns error hash" do
        result = introspector.call
        expect(result).to have_key(:error)
        expect(result[:error]).to be_a(String)
      end
    end
  end

  describe "#initialize" do
    it "stores application root and app reference" do
      app = double("Rails::Application", root: "/path/to/app")
      introspector = described_class.new(app)

      expect(introspector.instance_variable_get(:@app)).to eq(app)
      expect(introspector.instance_variable_get(:@root)).to eq("/path/to/app")
    end
  end
end
