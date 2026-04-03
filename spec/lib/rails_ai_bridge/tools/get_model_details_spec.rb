# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetModelDetails do
  let(:models_data) do
    {
      "User" => { table_name: "users", associations: [ { name: "posts", type: "has_many" } ], validations: [ { field: "name", type: "presence", attributes: [ "name" ] } ] },
      "Post" => { table_name: "posts", associations: [ { name: "user", type: "belongs_to" } ], validations: [] }
    }
  end

  before do
    allow(described_class).to receive(:cached_section).with(:models).and_return(models_data)
  end

  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  describe ".call" do
    context "when requesting a specific model" do
      let(:params) { { model: "User" } }

      it "returns full detail for that model" do
        expect(content).to include("# User")
        expect(content).to include("## Associations")
        expect(content).to include("- `has_many` **posts**")
        expect(content).to include("## Validations")
        expect(content).to include("- `` on name")
      end
    end

    context "with detail: 'summary'" do
      let(:params) { { detail: "summary" } }

      it "delegates to the SummaryFormatter" do
        expect(content).to include("# Available models (2)")
        expect(content).to include("- Post")
        expect(content).to include("- User")
      end
    end

    context "with detail: 'standard'" do
      let(:params) { { detail: "standard" } }

      it "delegates to the StandardFormatter" do
        expect(content).to include("- **User** — 1 associations, 1 validations")
        expect(content).to include("- **Post** — 1 associations, 0 validations")
      end
    end

    context "with detail: 'full'" do
      let(:params) { { detail: "full" } }

      it "delegates to the FullFormatter" do
        expect(content).to include("- **User** (table: users) — has_many :posts")
        expect(content).to include("- **Post** (table: posts) — belongs_to :user")
      end
    end

    context "when model is not found" do
      let(:params) { { model: "Missing" } }

      it "returns a helpful error message" do
        expect(content).to include("Model 'Missing' not found. Available: Post, User")
      end
    end
  end
end
