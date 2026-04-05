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
      expect(names).not_to include("User")
      expect(names).not_to include("Post")
    end
  end

  describe "#call" do
    it "returns core_entity when the model is listed in core_models" do
      classifier = described_class.new(core_model_names: [ "User" ], through_model_names: Set.new)
      result = classifier.call(User)
      expect(result[:tier]).to eq("core_entity")
      expect(result[:reason]).to eq("configured_core_model")
    end

    it "classifies a through join without payload as pure_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Categorization" ])
      )
      result = classifier.call(Categorization)
      expect(result[:tier]).to eq("pure_join")
    end

    it "classifies a through join with extra columns as rich_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Membership" ])
      )
      result = classifier.call(Membership)
      expect(result[:tier]).to eq("rich_join")
    end

    it "classifies a typical domain model as supporting" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: described_class.through_join_model_names
      )
      expect(classifier.call(Post)[:tier]).to eq("supporting")
      expect(classifier.call(User)[:tier]).to eq("supporting")
    end

    it "returns the correct reason string for pure_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Categorization" ])
      )
      result = classifier.call(Categorization)
      expect(result[:reason]).to eq("through_join_without_payload_columns")
    end

    it "returns the correct reason string for rich_join" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "Membership" ])
      )
      result = classifier.call(Membership)
      expect(result[:reason]).to eq("through_join_with_payload_columns")
    end

    it "returns the correct reason for supporting domain model" do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new
      )
      result = classifier.call(Post)
      expect(result[:tier]).to eq("supporting")
      expect(result[:reason]).to be_a(String)
    end

    it "accepts symbol core_model_names and converts them to strings" do
      classifier = described_class.new(
        core_model_names: [ :User ],
        through_model_names: Set.new
      )
      result = classifier.call(User)
      expect(result[:tier]).to eq("core_entity")
    end

    it "classifies a model as supporting when it is a through join but has only one belongs_to" do
      # Simulate a through join model that has only 1 belongs_to — should NOT be pure_join
      stub_model = Class.new do
        def self.name; "SingleBelongsJoin"; end
        def self.column_names; %w[id user_id created_at updated_at]; end
        def self.reflect_on_all_associations
          [double("assoc", macro: :belongs_to, foreign_key: "user_id")]
        end
        def self.inheritance_column; "type"; end
      end

      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new([ "SingleBelongsJoin" ])
      )
      result = classifier.call(stub_model)
      expect(result[:tier]).to eq("supporting")
    end

    it "classifies a model with extra payload columns but not a through join as supporting" do
      # A model with extra columns but not in through_model_names → supporting
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new  # Membership is NOT in through names
      )
      result = classifier.call(Membership)
      expect(result[:tier]).to eq("supporting")
      expect(result[:reason]).to eq("domain_or_misc_model")
    end
  end

  describe "BASE_METADATA constant" do
    it "includes standard timestamp and id columns" do
      expect(described_class::BASE_METADATA).to include("id", "created_at", "updated_at")
    end

    it "includes alternative timestamp column names" do
      expect(described_class::BASE_METADATA).to include("created_on", "updated_on")
    end

    it "is frozen" do
      expect(described_class::BASE_METADATA).to be_frozen
    end
  end
end