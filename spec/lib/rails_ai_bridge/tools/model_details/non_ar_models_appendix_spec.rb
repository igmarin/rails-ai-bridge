# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::ModelDetails::NonArModelsAppendix do
  describe ".entries_from" do
    it "returns rows for symbol keys" do
      section = { non_ar_models: [ { name: "Foo" } ] }
      expect(described_class.entries_from(section)).to eq([ { name: "Foo" } ])
    end

    it "returns rows for string keys (JSON-shaped payload)" do
      section = { "non_ar_models" => [ { "name" => "Bar" } ] }
      expect(described_class.entries_from(section)).to eq([ { "name" => "Bar" } ])
    end

    it "returns [] when string error key is present" do
      section = { "error" => "boom", "non_ar_models" => [ { "name" => "X" } ] }
      expect(described_class.entries_from(section)).to eq([])
    end

    it "prefers symbol :non_ar_models when both exist" do
      section = { non_ar_models: [ { name: "Sym" } ], "non_ar_models" => [ { "name" => "Str" } ] }
      expect(described_class.entries_from(section).first[:name]).to eq("Sym")
    end
  end
end
