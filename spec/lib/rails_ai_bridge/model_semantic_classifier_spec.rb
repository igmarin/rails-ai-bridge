# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ModelSemanticClassifier do
  before do
    # Load join models so +through:+ reflections are registered on parents.
    Membership
  end

  describe '.through_join_model_names' do
    it 'includes join models used in through associations' do
      names = described_class.through_join_model_names
      expect(names).to include('Categorization', 'Membership')
    end
  end

  describe '#call' do
    it 'returns core_entity when the model is listed in core_models' do
      classifier = described_class.new(core_model_names: ['User'], through_model_names: Set.new)
      result = classifier.call(User)
      expect(result[:tier]).to eq('core_entity')
      expect(result[:reason]).to eq('configured_core_model')
    end

    it 'classifies a through join without payload as pure_join' do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new(['Categorization'])
      )
      result = classifier.call(Categorization)
      expect(result[:tier]).to eq('pure_join')
    end

    it 'classifies a through join with extra columns as rich_join' do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: Set.new(['Membership'])
      )
      result = classifier.call(Membership)
      expect(result[:tier]).to eq('rich_join')
    end

    it 'classifies a typical domain model as supporting' do
      classifier = described_class.new(
        core_model_names: [],
        through_model_names: described_class.through_join_model_names
      )
      expect(classifier.call(Post)[:tier]).to eq('supporting')
      expect(classifier.call(User)[:tier]).to eq('supporting')
    end
  end
end
