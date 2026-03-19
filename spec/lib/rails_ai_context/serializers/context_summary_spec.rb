# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Serializers::ContextSummary do
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
