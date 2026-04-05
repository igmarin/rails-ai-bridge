# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetModelDetails do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      models = {
        "User" => {
          table_name: "users",
          associations: [ { type: "has_many", name: "posts" }, { type: "has_one", name: "profile" } ],
          validations: [ { kind: "presence", attributes: [ "email" ], options: {} } ]
        },
        "Post" => {
          table_name: "posts",
          associations: [ { type: "belongs_to", name: "user" } ],
          validations: []
        }
      }
      allow(described_class).to receive(:cached_section) do |sym|
        case sym
        when :models then models
        when :non_ar_models then { non_ar_models: [] }
        end
      end
    end

    it "returns names only with detail:summary" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("- Post")
      expect(text).to include("- User")
      expect(text).not_to include("associations")
    end

    it "returns names with counts for detail:standard" do
      result = described_class.call(detail: "standard")
      text = result.content.first[:text]
      expect(text).to include("**User**")
      expect(text).to include("2 associations")
      expect(text).to include("1 validations")
    end

    it "returns names with association list for detail:full" do
      result = described_class.call(detail: "full")
      text = result.content.first[:text]
      expect(text).to include("**User**")
      expect(text).to include("has_many :posts")
    end

    it "always returns full detail for specific model" do
      result = described_class.call(model: "User", detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("# User")
      expect(text).to include("## Associations")
      expect(text).to include("has_many")
    end

    it "supports case-insensitive model lookup" do
      result = described_class.call(model: "user")
      text = result.content.first[:text]
      expect(text).to include("# User")
    end

    it "handles missing models gracefully" do
      allow(described_class).to receive(:cached_section) do |sym|
        case sym
        when :models then nil
        when :non_ar_models then { non_ar_models: [] }
        end
      end
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]
      expect(text).to include("not available")
    end
  end
end
