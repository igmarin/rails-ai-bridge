# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetModelDetails do
  let(:models_data) do
    {
      "User" => { table_name: "users", associations: [ { name: "posts", type: "has_many" } ], validations: [ { field: "name", type: "presence", attributes: [ "name" ] } ] },
      "Post" => { table_name: "posts", associations: [ { name: "user", type: "belongs_to" } ], validations: [] }
    }
  end

  let(:non_ar_empty) { { non_ar_models: [] } }

  before do
    allow(described_class).to receive(:cached_section) do |sym|
      case sym
      when :models then models_data
      when :non_ar_models then non_ar_empty
      end
    end
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
        expect(content).to include("Model 'Missing' not found. Available AR: Post, User")
      end
    end

    context "when requesting a non-ActiveRecord class under app/models" do
      let(:non_ar_empty) do
        {
          non_ar_models: [
            { name: "OrderCalculator", relative_path: "app/models/order_calculator.rb", tag: "POJO/Service" }
          ]
        }
      end

      let(:params) { { model: "OrderCalculator" } }

      it "returns a POJO/Service detail stub" do
        expect(content).to include("# OrderCalculator (POJO/Service)")
        expect(content).to include("app/models/order_calculator.rb")
      end
    end

    context "when non_ar_models section has entries in a listing" do
      let(:non_ar_empty) do
        {
          non_ar_models: [
            { name: "OrderCalculator", relative_path: "app/models/order_calculator.rb", tag: "POJO/Service" }
          ]
        }
      end
      let(:params) { { detail: "summary" } }

      it "appends a Non-ActiveRecord section" do
        expect(content).to include("## Non-ActiveRecord classes")
        expect(content).to include("OrderCalculator")
        expect(content).to include("[POJO/Service]")
      end
    end
  end
end
