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

  let(:models_with_tiers) do
    {
      "User" => {
        table_name: "users",
        semantic_tier: "core_entity",
        semantic_tier_reason: "configured_core_model",
        associations: [ { type: "has_many", name: "posts" } ],
        validations: [ { kind: "presence", attributes: [ "email" ], options: {} } ]
      },
      "Categorization" => {
        table_name: "categorizations",
        semantic_tier: "pure_join",
        semantic_tier_reason: "through_join_without_payload_columns",
        associations: [
          { type: "belongs_to", name: "post" },
          { type: "belongs_to", name: "category" }
        ],
        validations: []
      },
      "Membership" => {
        table_name: "memberships",
        semantic_tier: "rich_join",
        semantic_tier_reason: "through_join_with_payload_columns",
        associations: [
          { type: "belongs_to", name: "user" },
          { type: "belongs_to", name: "group" }
        ],
        validations: []
      },
      "Post" => {
        table_name: "posts",
        semantic_tier: "supporting",
        semantic_tier_reason: "domain_or_misc_model",
        associations: [ { type: "belongs_to", name: "user" } ],
        validations: [],
        error: nil
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

    context "with semantic tiers" do
      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "appends tier suffix to each model name" do
        expect(output).to include("- User (core_entity)")
        expect(output).to include("- Categorization (pure_join)")
        expect(output).to include("- Membership (rich_join)")
        expect(output).to include("- Post (supporting)")
      end

      it "sorts model names alphabetically" do
        lines = output.lines.map(&:chomp).select { |l| l.start_with?("- ") }
        names = lines.map { |l| l.split(" ").first(2).last }
        expect(names).to eq(names.sort)
      end
    end

    context "without semantic tiers" do
      it "does not include parenthetical tier suffix" do
        expect(output).not_to match(/\(core_entity\)|\(pure_join\)|\(rich_join\)|\(supporting\)/)
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

    context "with semantic tiers" do
      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "shows tier annotation for core_entity" do
        expect(output).to include("**User** — tier: core_entity")
      end

      it "shows tier annotation for pure_join" do
        expect(output).to include("**Categorization** — tier: pure_join")
      end

      it "shows tier annotation for rich_join" do
        expect(output).to include("**Membership** — tier: rich_join")
      end

      it "shows tier annotation for supporting" do
        expect(output).to include("**Post** — tier: supporting")
      end

      it "skips models with :error key" do
        models_with_error = { "Broken" => { error: "table missing" } }
        out = described_class.new(models: models_with_error).call
        expect(out).not_to include("Broken")
      end
    end

    context "without semantic tiers" do
      it "does not render tier annotation" do
        expect(output).not_to include("tier:")
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

    context "with semantic tiers" do
      subject(:output) { described_class.new(models: models_with_tiers).call }

      it "shows tier annotation for core_entity models" do
        expect(output).to include("**User** (table: users) — tier: core_entity")
      end

      it "shows tier annotation for pure_join models" do
        expect(output).to include("**Categorization** (table: categorizations) — tier: pure_join")
      end

      it "shows tier annotation for rich_join models" do
        expect(output).to include("**Membership** (table: memberships) — tier: rich_join")
      end

      it "skips models with :error key" do
        models_with_error = { "Broken" => { error: "connection failed" } }
        out = described_class.new(models: models_with_error).call
        expect(out).not_to include("Broken")
      end
    end

    context "without semantic tiers" do
      it "does not render tier annotation" do
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

    context "with semantic_tier present" do
      subject(:output) { described_class.new(name: "User", data: models_with_tiers["User"]).call }

      it "renders semantic tier as bold label" do
        expect(output).to include("**Semantic tier:** `core_entity`")
      end

      it "renders tier reason" do
        expect(output).to include("**Tier reason:** configured_core_model")
      end
    end

    context "with pure_join tier" do
      subject(:output) { described_class.new(name: "Categorization", data: models_with_tiers["Categorization"]).call }

      it "renders the correct tier" do
        expect(output).to include("**Semantic tier:** `pure_join`")
      end

      it "renders the correct reason" do
        expect(output).to include("**Tier reason:** through_join_without_payload_columns")
      end
    end

    context "without semantic_tier" do
      it "does not render Semantic tier section" do
        expect(output).not_to include("Semantic tier")
        expect(output).not_to include("Tier reason")
      end
    end

    context "with semantic_tier but no reason" do
      subject(:output) do
        data = models_with_tiers["User"].merge(semantic_tier_reason: nil)
        described_class.new(name: "User", data: data).call
      end

      it "renders tier but omits reason line" do
        expect(output).to include("**Semantic tier:** `core_entity`")
        expect(output).not_to include("Tier reason")
      end
    end
  end
end