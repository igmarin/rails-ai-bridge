# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Tools::GetRoutes do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      by_controller = {
        "users" => [
          { verb: "GET", path: "/users", action: "index", name: "users" },
          { verb: "GET", path: "/users/:id", action: "show", name: "user" },
          { verb: "POST", path: "/users", action: "create", name: nil }
        ],
        "posts" => [
          { verb: "GET", path: "/posts", action: "index", name: "posts" },
          { verb: "GET", path: "/posts/:id", action: "show", name: "post" }
        ],
        "api/v1/items" => [
          { verb: "GET", path: "/api/v1/items", action: "index", name: "api_v1_items" }
        ]
      }
      allow(described_class).to receive(:cached_context).and_return({
        routes: { total_routes: 6, by_controller: by_controller, api_namespaces: [ "api/v1" ] }
      })
    end

    it "returns summary with route counts per controller" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("Routes Summary (6 total)")
      expect(text).to include("**users**")
      expect(text).to include("3 routes")
      expect(text).to include("api/v1")
    end

    it "returns standard detail with paths" do
      result = described_class.call(detail: "standard")
      text = result.content.first[:text]
      expect(text).to include("Routes (6 total)")
      expect(text).to include("`GET`")
      expect(text).to include("/users")
    end

    it "returns full detail with route names" do
      result = described_class.call(detail: "full")
      text = result.content.first[:text]
      expect(text).to include("Routes Full Detail")
      expect(text).to include("| Verb |")
      expect(text).to include("users")
    end

    it "filters by controller" do
      result = described_class.call(controller: "posts", detail: "standard")
      text = result.content.first[:text]
      expect(text).to include("/posts")
      expect(text).not_to include("/users")
    end

    it "case-insensitive controller filter" do
      result = described_class.call(controller: "USERS", detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("**users**")
    end

    it "returns error for unknown controller" do
      result = described_class.call(controller: "nonexistent")
      text = result.content.first[:text]
      expect(text).to include("No routes for")
    end

    it "handles missing routes gracefully" do
      allow(described_class).to receive(:cached_context).and_return({})
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("not available")
    end
  end
end
