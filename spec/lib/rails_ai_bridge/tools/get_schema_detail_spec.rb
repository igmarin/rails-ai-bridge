# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetSchema do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      tables = 50.times.each_with_object({}) do |i, h|
        h["table_#{i.to_s.rjust(3, '0')}"] = {
          columns: 10.times.map { |j| { name: "col_#{j}", type: "string", null: true } },
          indexes: [ { name: "idx_#{i}", columns: [ "col_0" ], unique: false } ],
          foreign_keys: []
        }
      end
      allow(described_class).to receive(:cached_context).and_return({
        schema: { adapter: "postgresql", tables: tables, total_tables: 50 }
      })
    end

    it "returns compact summary with detail:summary" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("Schema Summary (50 tables)")
      expect(text).to include("10 columns")
      expect(text).not_to include("| Column |")
    end

    it "returns column names with detail:standard" do
      result = described_class.call(detail: "standard", limit: 3)
      text = result.content.first[:text]
      expect(text).to include("showing 3")
      expect(text).to include("col_0:string")
    end

    it "returns full detail with detail:full" do
      result = described_class.call(detail: "full", limit: 2)
      text = result.content.first[:text]
      expect(text).to include("Full Detail")
      expect(text).to include("| Column |")
    end

    it "paginates with offset" do
      result = described_class.call(detail: "summary", limit: 10, offset: 45)
      text = result.content.first[:text]
      expect(text).to include("table_045")
      expect(text).not_to include("table_000")
    end

    it "returns full detail for specific table regardless of detail param" do
      result = described_class.call(table: "table_000", detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("Table: table_000")
      expect(text).to include("| Column |")
    end

    it "handles missing schema gracefully" do
      allow(described_class).to receive(:cached_context).and_return({})
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("not available")
    end

    it "handles schema error gracefully" do
      allow(described_class).to receive(:cached_context).and_return({
        schema: { error: "no database" }
      })
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("no database")
    end

    it "returns pagination hint when more tables exist" do
      result = described_class.call(detail: "summary", limit: 10)
      text = result.content.first[:text]
      expect(text).to include("offset:")
    end

    it "returns json format for full detail" do
      result = described_class.call(detail: "full", format: "json")
      text = result.content.first[:text]
      parsed = JSON.parse(text)
      expect(parsed).to have_key("tables")
    end
  end
end
