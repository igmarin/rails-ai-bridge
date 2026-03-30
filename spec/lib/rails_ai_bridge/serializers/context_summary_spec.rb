# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::ContextSummary do
  describe ".test_command" do
    it "returns 'bundle exec rspec' for rspec framework" do
      context = { tests: { framework: "rspec" } }
      expect(described_class.test_command(context)).to eq("bundle exec rspec")
    end

    it "returns 'bin/rails test' for minitest framework" do
      context = { tests: { framework: "minitest" } }
      expect(described_class.test_command(context)).to eq("bin/rails test")
    end

    it "returns 'bundle exec rspec' when framework is unknown" do
      context = { tests: { framework: "unknown" } }
      expect(described_class.test_command(context)).to eq("bundle exec rspec")
    end

    it "returns 'bundle exec rspec' when tests key is missing" do
      expect(described_class.test_command({})).to eq("bundle exec rspec")
    end

    it "returns 'bundle exec rspec' when framework is nil" do
      context = { tests: { framework: nil } }
      expect(described_class.test_command(context)).to eq("bundle exec rspec")
    end

    it "returns 'bundle exec rspec' when framework is an empty string" do
      context = { tests: { framework: "" } }
      expect(described_class.test_command(context)).to eq("bundle exec rspec")
    end

    it "returns 'bundle exec rspec' when framework is whitespace only" do
      context = { tests: { framework: "   " } }
      expect(described_class.test_command(context)).to eq("bundle exec rspec")
    end
  end

  describe ".model_complexity_score" do
    it "sums associations, validations, callbacks, and scopes sizes" do
      data = {
        associations: [ {}, {}, {} ],
        validations:  [ {}, {} ],
        callbacks:    [ {} ],
        scopes:       [ {}, {} ]
      }
      expect(described_class.model_complexity_score(data)).to eq(8)
    end

    it "returns 0 for an empty model" do
      expect(described_class.model_complexity_score({})).to eq(0)
    end

    it "preserves insertion order for models with identical scores (stable sort)" do
      models = {
        "AardvarkModel" => { associations: [ {} ], validations: [], callbacks: [], scopes: [] },
        "BeeModel"      => { associations: [ {} ], validations: [], callbacks: [], scopes: [] }
      }
      sorted = models.sort_by { |_n, d| -described_class.model_complexity_score(d) }.map(&:first)
      expect(sorted).to eq(%w[AardvarkModel BeeModel])
    end

    it "handles unexpected non-array values via Array() coercion" do
      data = { associations: "bad_value", validations: nil, callbacks: [], scopes: [] }
      expect { described_class.model_complexity_score(data) }.not_to raise_error
    end
  end

  describe ".routes_stack_line" do
    it "uses introspected controller count to match split rule headings" do
      context = {
        routes: { total_routes: 100, error: false, by_controller: 350.times.index_with { [] } },
        controllers: {
          error: false,
          controllers: 341.times.index_with { { actions: %w[index] } }
        }
      }

      line = described_class.routes_stack_line(context)
      expect(line).to include("341 controller classes")
      expect(line).to include("350 names in routing")
    end

    it "falls back to route targets when controller introspection is missing" do
      context = {
        routes: { total_routes: 12, error: false, by_controller: { "a" => [], "b" => [] } }
      }

      line = described_class.routes_stack_line(context)
      expect(line).to eq("- Routes: 12 total — 2 route targets (controller inventory unavailable)")
    end
  end
end
