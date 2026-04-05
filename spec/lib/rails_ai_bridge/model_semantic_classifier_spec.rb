# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::ModelSemanticClassifier do
  before do
    # Load join models so +through:+ reflections are registered on parents.
    Categorization
    Membership
  end

  describe ".through_join_model_names" do
    it "includes join models used in through associations" do
      names = described_class.through_join_model_names
      expect(names).to include("Categorization", "Membership")
    end

    it "returns a Set" do
      expect(described_class.through_join_model_names).to be_a(Set)
    end

    it "does not include non-join models" do
      names = described_class.through_join_model_names
      expect(names).not_to include("User", "Post", "Category", "Group")
    end
  end

  describe "#call" do
    it "returns core_entity when the model is listed in core_models" do
      classifier = described_class.new(core_model_names: [ "User" ], through_model_names: Set.new)
      result = classifier.call(User)
      expect(result[:tier]).to eq("core_entity")
      expect(result[:reason]).to eq("configured_core_model")
    end

    it "returns both :tier and :reason keys" do
      classifier = described_class.new(core_model_names: [], through_model_names: Set.new)
      result = classifier.call(User)
      expect(result).to have_key(:tier)
      expect(result).to have_key(:reason)
    end

    it "classifies a through join without payload as pure_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Categorization" ])
      )
      result = classifier.call(Categorization)
      expect(result[:tier]).to eq("pure_join")
    end

    it "returns the correct reason for pure_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Categorization" ])
      )
      expect(classifier.call(Categorization)[:reason]).to eq("through_join_without_payload_columns")
    end

    it "classifies a through join with extra columns as rich_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Membership" ])
      )
      result = classifier.call(Membership)
      expect(result[:tier]).to eq("rich_join")
    end

    it "returns the correct reason for rich_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Membership" ])
      )
      expect(classifier.call(Membership)[:reason]).to eq("through_join_with_payload_columns")
    end

    it "classifies a typical domain model as supporting" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: described_class.through_join_model_names
      )
      expect(classifier.call(Post)[:tier]).to eq("supporting")
      expect(classifier.call(User)[:tier]).to eq("supporting")
    end

    it "accepts symbol names in core_model_names and converts them to strings" do
      classifier = described_class.new(core_model_names: [ :User ], through_model_names: Set.new)
      expect(classifier.call(User)[:tier]).to eq("core_entity")
    end

    it "accepts symbol names in through_model_names and converts them to strings" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ :Categorization ])
      )
      expect(classifier.call(Categorization)[:tier]).to eq("pure_join")
    end

    it "returns supporting with not_classified_as_join_table when a through model has only one belongs_to" do
      # Categorization is a through join model but simulate only 1 belongs_to by using a classifier
      # where the model is marked as through but we test the logic via a stub model
      stub_model = Class.new do
        def self.name; "StubJoin"; end
        def self.column_names; %w[id stub_id other_id created_at updated_at]; end
        def self.reflect_on_all_associations
          [
            double("assoc", macro: :belongs_to, foreign_key: "stub_id")
          ]
        end
        def self.inheritance_column; "type"; end
      end
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "StubJoin" ])
      )
      result = classifier.call(stub_model)
      expect(result[:tier]).to eq("supporting")
      expect(result[:reason]).to eq("not_classified_as_join_table")
    end

    it "returns supporting with domain_or_misc_model when a non-through model has extra columns" do
      stub_model = Class.new do
        def self.name; "StubDomain"; end
        def self.column_names; %w[id name role user_id created_at updated_at]; end
        def self.reflect_on_all_associations
          [ double("assoc", macro: :belongs_to, foreign_key: "user_id") ]
        end
        def self.inheritance_column; "type"; end
      end
      classifier = described_class.new(core_model_names: [], through_model_names: Set.new)
      result = classifier.call(stub_model)
      expect(result[:tier]).to eq("supporting")
      expect(result[:reason]).to eq("domain_or_misc_model")
    end

    it "returns supporting with no_columns_loaded when model raises on column_names" do
      stub_model = Class.new do
        def self.name; "StubBroken"; end
        def self.column_names; raise ActiveRecord::StatementInvalid, "table missing"; end
        def self.reflect_on_all_associations; []; end
        def self.inheritance_column; "type"; end
      end
      classifier = described_class.new(core_model_names: [], through_model_names: Set.new)
      result = classifier.call(stub_model)
      expect(result[:tier]).to eq("supporting")
      expect(result[:reason]).to eq("no_columns_loaded")
    end

    it "core_entity takes precedence over through join membership" do
      classifier = described_class.new(
        core_model_names: [ "Categorization" ],
        through_model_names: Set.new([ "Categorization" ])
      )
      expect(classifier.call(Categorization)[:tier]).to eq("core_entity")
    end
  end

  describe "BASE_METADATA constant" do
    it "includes standard timestamp and id columns" do
      expect(described_class::BASE_METADATA).to include("id", "created_at", "updated_at")
    end

    it "includes created_on and updated_on for date-based timestamps" do
      expect(described_class::BASE_METADATA).to include("created_on", "updated_on")
    end

    it "is frozen" do
      expect(described_class::BASE_METADATA).to be_frozen
    end
  end
end