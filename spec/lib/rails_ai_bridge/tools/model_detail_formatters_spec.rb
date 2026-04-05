# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RailsAiBridge::Tools::ModelDetails formatters" do
  let(:models) do
    {
      "User" => {
        table_name: "users",
        associations: [
          { type: "has_many", name: "posts" },
          { type: "has_one", name: "profile" }
        ],
        validations: [
          { kind: "presence", attributes: [ "email" ], options: {} }
        ],
        enums: { role: [ "admin", "member" ] },
        scopes: [ "active", "recent" ],
        callbacks: { before_save: [ "encrypt_password" ] },
        concerns: [ "Trackable" ],
        instance_methods: [ "full_name" ]
      },
      "Post" => {
        table_name: "posts",
        associations: [ { type: "belongs_to", name: "user" } ],
        validations: []
      }
    }
  end

  describe RailsAiBridge::Tools::ModelDetails::SummaryFormatter do
    subject(:output) { described_class.new(models: models).call }

    it "lists model names" do
      expect(output).to include("- Post")
      expect(output).to include("- User")
    end

    it "includes total count" do
      expect(output).to include("2")
    end

    it "does not include association counts or details" do
      expect(output).not_to include("associations")
    end

    context "with semantic_tier in model data" do
      let(:models_with_tiers) do
        {
          "User" => { table_name: "users", semantic_tier: "core_entity" },
          "Membership" => { table_name: "memberships", semantic_tier: "rich_join" },
          "Categorization" => { table_name: "categorizations", semantic_tier: "pure_join" },
          "Post" => { table_name: "posts", semantic_tier: "supporting" }
        }
      end

      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "appends tier suffix to each model entry" do
        expect(output).to include("- User (core_entity)")
        expect(output).to include("- Membership (rich_join)")
        expect(output).to include("- Categorization (pure_join)")
        expect(output).to include("- Post (supporting)")
      end

      it "sorts model names alphabetically" do
        lines = output.lines.map(&:chomp).select { |l| l.start_with?("- ") }
        names = lines.map { |l| l.sub(/^- (\w+).*/, '\1') }
        expect(names).to eq(names.sort)
      end
    end

    context "without semantic_tier in model data" do
      it "renders model names without tier suffix" do
        # The base models fixture has no :semantic_tier key
        expect(output).not_to match(/- User \(/)
        expect(output).not_to match(/- Post \(/)
      end
    end

    context "when model data is not a Hash" do
      let(:models_non_hash) { { "Plain" => nil } }

      it "renders model name without tier suffix" do
        output = described_class.new(models: models_non_hash).call
        expect(output).to include("- Plain")
        expect(output).not_to include("- Plain (")
      end
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::StandardFormatter do
    subject(:output) { described_class.new(models: models).call }

    it "includes model names in bold" do
      expect(output).to include("**User**")
      expect(output).to include("**Post**")
    end

    it "includes association and validation counts for User" do
      expect(output).to include("2 associations")
      expect(output).to include("1 validations")
    end

    it "includes a hint to use model: for full detail" do
      expect(output).to include("model:\"Name\"")
    end

    context "with semantic_tier in model data" do
      let(:models_with_tiers) do
        {
          "User" => {
            table_name: "users",
            semantic_tier: "core_entity",
            associations: [],
            validations: []
          },
          "Membership" => {
            table_name: "memberships",
            semantic_tier: "rich_join",
            associations: [ { type: "belongs_to", name: "user" }, { type: "belongs_to", name: "group" } ],
            validations: []
          }
        }
      end

      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "includes tier annotation after model name" do
        expect(output).to include("**User** — tier: core_entity")
        expect(output).to include("**Membership** — tier: rich_join")
      end
    end

    context "when model data contains :error key" do
      let(:models_with_error) do
        {
          "BrokenModel" => { error: "Failed to load" },
          "User" => { table_name: "users", associations: [], validations: [] }
        }
      end

      subject(:output) { described_class.new(models: models_with_error).call }

      it "omits the errored model from output" do
        expect(output).not_to include("BrokenModel")
        expect(output).to include("**User**")
      end
    end

    context "when model has no associations or validations" do
      let(:models_empty_counts) do
        { "EmptyModel" => { table_name: "empty_models", associations: [], validations: [] } }
      end

      subject(:output) { described_class.new(models: models_empty_counts).call }

      it "omits count suffix when both counts are zero" do
        expect(output).not_to include("0 associations")
        expect(output).not_to include("0 validations")
      end
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::FullFormatter do
    subject(:output) { described_class.new(models: models).call }

    it "includes model names in bold" do
      expect(output).to include("**User**")
    end

    it "includes association type and name" do
      expect(output).to include("has_many :posts")
    end

    it "includes table name" do
      expect(output).to include("table: users")
    end

    it "includes navigation hint" do
      expect(output).to include("model:\"Name\"")
    end

    context "with semantic_tier in model data" do
      let(:models_with_tiers) do
        {
          "User" => {
            table_name: "users",
            semantic_tier: "core_entity",
            associations: [ { type: "has_many", name: "posts" } ]
          }
        }
      end

      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "includes tier annotation in model line" do
        expect(output).to include("— tier: core_entity")
      end

      it "places tier annotation after table name" do
        expect(output).to match(/\(table: users\).*tier: core_entity/)
      end
    end

    context "when model data contains :error key" do
      let(:models_with_error) do
        {
          "BrokenModel" => { error: "Could not introspect" },
          "Post" => { table_name: "posts", associations: [] }
        }
      end

      subject(:output) { described_class.new(models: models_with_error).call }

      it "omits the errored model from output" do
        expect(output).not_to include("BrokenModel")
        expect(output).to include("**Post**")
      end
    end

    context "when model has no semantic_tier" do
      it "does not include tier annotation" do
        expect(output).not_to include("tier:")
      end
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::SingleModelFormatter do
    subject(:output) { described_class.new(name: "User", data: models["User"]).call }

    it "renders model name as top-level header" do
      expect(output).to include("# User")
    end

    it "renders table name" do
      expect(output).to include("**Table:** `users`")
    end

    it "renders associations section" do
      expect(output).to include("## Associations")
      expect(output).to include("`has_many` **posts**")
    end

    it "renders validations section" do
      expect(output).to include("## Validations")
      expect(output).to include("`presence` on email")
    end

    it "renders enums section" do
      expect(output).to include("## Enums")
      expect(output).to include("`role`: admin, member")
    end

    it "renders scopes section" do
      expect(output).to include("## Scopes")
      expect(output).to include("`active`")
    end

    it "renders callbacks section" do
      expect(output).to include("## Callbacks")
      expect(output).to include("`before_save`: encrypt_password")
    end

    it "renders concerns section" do
      expect(output).to include("## Concerns")
      expect(output).to include("Trackable")
    end

    it "renders instance methods section" do
      expect(output).to include("## Key instance methods")
      expect(output).to include("`full_name`")
    end

    context "with semantic_tier in model data" do
      let(:data_with_tier) do
        models["User"].merge(
          semantic_tier: "core_entity",
          semantic_tier_reason: "configured_core_model"
        )
      end

      subject(:output) { described_class.new(name: "User", data: data_with_tier).call }

      it "renders semantic tier section" do
        expect(output).to include("**Semantic tier:** `core_entity`")
      end

      it "renders tier reason when present" do
        expect(output).to include("**Tier reason:** configured_core_model")
      end
    end

    context "with semantic_tier but no tier reason" do
      let(:data_with_tier_no_reason) do
        models["User"].merge(semantic_tier: "supporting")
      end

      subject(:output) { described_class.new(name: "User", data: data_with_tier_no_reason).call }

      it "renders semantic tier without reason line" do
        expect(output).to include("**Semantic tier:** `supporting`")
        expect(output).not_to include("**Tier reason:**")
      end
    end

    context "without semantic_tier" do
      it "does not render semantic tier section" do
        expect(output).not_to include("**Semantic tier:**")
        expect(output).not_to include("**Tier reason:**")
      end
    end

    context "with rich_join tier" do
      let(:data_rich_join) do
        {
          table_name: "memberships",
          semantic_tier: "rich_join",
          semantic_tier_reason: "through_join_with_payload_columns",
          associations: [
            { type: "belongs_to", name: "user" },
            { type: "belongs_to", name: "group" }
          ],
          validations: []
        }
      end

      subject(:output) { described_class.new(name: "Membership", data: data_rich_join).call }

      it "renders the rich_join tier correctly" do
        expect(output).to include("**Semantic tier:** `rich_join`")
        expect(output).to include("**Tier reason:** through_join_with_payload_columns")
      end
    end
  end
end