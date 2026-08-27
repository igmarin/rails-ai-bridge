# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ModelSemanticClassifier do
  before do
    # Force Zeitwerk to load the join models and their parent models so +through:+
    # reflections are registered before .through_join_model_names scans descendants.
    [User, Group, Membership, Post, Category, Categorization].each(&:itself)
  end

  describe '.through_join_model_names' do
    it 'includes join models used in through associations' do
      names = described_class.through_join_model_names
      expect(names).to include('Categorization', 'Membership')
    end

    it 'skips abstract, unnamed, and unresolvable models when scanning descendants' do
      abstract = double('abstract', abstract_class?: true, name: 'Abstract', reflect_on_all_associations: [])
      unnamed = double('unnamed', abstract_class?: false, name: nil, reflect_on_all_associations: [])
      plain = double('plain', abstract_class?: false, name: 'Plain',
                              reflect_on_all_associations: [double('assoc', options: {})],
                              reflect_on_association: nil)
      dangling = double('dangling', abstract_class?: false, name: 'Dangling',
                                    reflect_on_all_associations: [double('assoc', options: { through: :missing })],
                                    reflect_on_association: nil)

      allow(ActiveRecord::Base).to receive(:descendants).and_return([abstract, unnamed, plain, dangling])

      expect(described_class.through_join_model_names).to be_empty
    end

    it 'skips descendants whose reflection raises' do
      broken = double('broken', abstract_class?: false, name: 'Broken')
      allow(broken).to receive(:reflect_on_all_associations).and_raise('boom')

      allow(ActiveRecord::Base).to receive(:descendants).and_return([broken])

      expect(described_class.through_join_model_names).to be_empty
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

    it 'classifies an unnamed model as supporting' do
      result = described_class.new.call(Class.new)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to eq('unnamed_model')
    end

    it 'classifies a model with no loadable columns as supporting' do
      model = double('model', name: 'Columnless', column_names: [])

      result = described_class.new.call(model)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to eq('no_columns_loaded')
    end

    it 'returns no_columns_loaded when column_names raises' do
      model = double('model', name: 'Boom')
      allow(model).to receive(:column_names).and_raise('db unavailable')

      result = described_class.new.call(model)

      expect(result[:reason]).to eq('no_columns_loaded')
    end

    it 'returns a classification_error tier when reflection raises' do
      model = double('model', name: 'Broken', column_names: %w[id])
      allow(model).to receive(:reflect_on_all_associations).and_raise('boom')

      result = described_class.new.call(model)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to start_with('classification_error:')
    end

    it 'classifies a non-through model without payload columns as supporting' do
      assoc = double('belongs', macro: :belongs_to, foreign_key: 'user_id')
      model = double('model', name: 'Tagging',
                              column_names: %w[id user_id created_at updated_at],
                              reflect_on_all_associations: [assoc],
                              inheritance_column: 'type')

      result = described_class.new.call(model)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to eq('not_classified_as_join_table')
    end

    it 'classifies a through model with fewer than two belongs_to as supporting' do
      assoc = double('belongs', macro: :belongs_to, foreign_key: 'user_id')
      model = double('model', name: 'Follower',
                              column_names: %w[id user_id note lock_version],
                              reflect_on_all_associations: [assoc],
                              inheritance_column: 'type')
      classifier = described_class.new(through_model_names: Set.new(['Follower']))

      result = classifier.call(model)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to eq('domain_or_misc_model')
    end

    it 'treats the inheritance column and lock_version as metadata' do
      model = double('model', name: 'StiModel',
                              column_names: %w[id type lock_version],
                              reflect_on_all_associations: [],
                              inheritance_column: 'type')
      classifier = described_class.new(through_model_names: Set.new(['StiModel']))

      result = classifier.call(model)

      expect(result[:tier]).to eq('supporting')
      expect(result[:reason]).to eq('not_classified_as_join_table')
    end
  end
end
