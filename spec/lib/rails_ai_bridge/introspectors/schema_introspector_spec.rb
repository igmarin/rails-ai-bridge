# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::SchemaIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "returns a hash with schema data" do
      expect(result).to be_a(Hash)
    end

    it "includes the adapter name" do
      expect(result[:adapter]).to be_a(String)
    end

    it "includes tables from the test schema" do
      expect(result[:tables]).to have_key("users")
      expect(result[:tables]).to have_key("posts")
    end

    it "reports total_tables count" do
      expect(result[:total_tables]).to eq(result[:tables].size)
    end

    context "with excluded_tables configured" do
      # A fresh introspector is required so @table_names is not memoized from
      # a prior example that ran before excluded_tables was set.
      subject(:result) { described_class.new(Rails.application).call }

      before { RailsAiBridge.configuration.excluded_tables << "users" }
      after  { RailsAiBridge.configuration.excluded_tables.clear }

      it "omits the excluded table from the result" do
        expect(result[:tables]).not_to have_key("users")
      end

      it "still includes non-excluded tables" do
        expect(result[:tables]).to have_key("posts")
      end

      it "reflects the reduced count in total_tables" do
        expect(result[:total_tables]).to eq(result[:tables].size)
        expect(result[:total_tables]).to be < 2
      end
    end

    context "with a glob excluded_tables pattern" do
      subject(:result) { described_class.new(Rails.application).call }

      before { RailsAiBridge.configuration.excluded_tables << "post*" }
      after  { RailsAiBridge.configuration.excluded_tables.clear }

      it "omits tables matching the glob" do
        expect(result[:tables]).not_to have_key("posts")
      end

      it "keeps tables not matching the glob" do
        expect(result[:tables]).to have_key("users")
      end
    end

    context "when ActiveRecord is not connected (static parse fallback)" do
      subject(:result) { introspector.call }

      before do
        allow(introspector).to receive(:active_record_connected?).and_return(false)
      end

      it "returns the static_parse adapter" do
        expect(result[:adapter]).to eq("static_parse")
      end

      it "includes a note about the parse source" do
        expect(result[:note]).to include("schema.rb")
      end

      it "includes tables from schema.rb" do
        expect(result[:tables]).to have_key("users")
        expect(result[:tables]).to have_key("posts")
      end

      it "total_tables matches the parsed table count" do
        expect(result[:total_tables]).to eq(result[:tables].size)
      end
    end

    context "when schema.rb is absent" do
      before do
        allow(introspector).to receive(:active_record_connected?).and_return(false)
        allow(introspector).to receive(:schema_file_path).and_return("/nonexistent/schema.rb")
      end

      it "returns an error hash" do
        expect(introspector.call[:error]).to include("schema.rb")
      end
    end
  end
end
