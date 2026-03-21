# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetControllers do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      controllers = {
        "UsersController" => {
          actions: %w[index show create],
          filters: [ { kind: "before_action", name: "authenticate_user!" } ],
          strong_params: %w[name email],
          parent_class: "ApplicationController"
        },
        "PostsController" => {
          actions: %w[index show],
          filters: [],
          strong_params: %w[title body]
        }
      }
      allow(described_class).to receive(:cached_context).and_return({
        controllers: { controllers: controllers }
      })
    end

    it "returns names with action counts for detail:summary" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("**UsersController** — 3 actions")
      expect(text).to include("**PostsController** — 2 actions")
    end

    it "returns names with action names for detail:standard" do
      result = described_class.call(detail: "standard")
      text = result.content.first[:text]
      expect(text).to include("**UsersController** — index, show, create")
    end

    it "returns everything for detail:full" do
      result = described_class.call(detail: "full")
      text = result.content.first[:text]
      expect(text).to include("## UsersController")
      expect(text).to include("Filters:")
      expect(text).to include("authenticate_user!")
    end

    it "always returns full detail for specific controller" do
      result = described_class.call(controller: "UsersController", detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("# UsersController")
      expect(text).to include("## Actions")
      expect(text).to include("## Filters")
    end

    it "supports case-insensitive controller lookup" do
      result = described_class.call(controller: "userscontroller")
      text = result.content.first[:text]
      expect(text).to include("# UsersController")
    end

    it "handles missing controllers gracefully" do
      allow(described_class).to receive(:cached_context).and_return({})
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("not available")
    end
  end
end
