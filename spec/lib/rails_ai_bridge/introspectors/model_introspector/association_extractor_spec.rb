# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ModelIntrospector::AssociationExtractor do
  let(:model) { double('Model', respond_to?: true) }
  let(:extractor) { described_class.new(model) }

  describe '#call' do
    it 'returns an empty array when model does not support reflect_on_all_associations' do
      allow(model).to receive(:reflect_on_all_associations).and_raise(NoMethodError)
      expect(extractor.call).to eq([])
    end

    it 'returns an empty array on standard error' do
      allow(model).to receive(:reflect_on_all_associations).and_raise(StandardError)
      expect(extractor.call).to eq([])
    end

    it 'extracts association details correctly' do
      assoc = double(
        'Association',
        name: :posts,
        macro: :has_many,
        class_name: 'Post',
        foreign_key: 'user_id',
        options: { polymorphic: true, optional: true, through: :user_posts, dependent: :destroy }
      )
      allow(model).to receive(:reflect_on_all_associations).and_return([assoc])

      result = extractor.call
      expect(result.size).to eq(1)

      detail = result.first
      expect(detail[:name]).to eq('posts')
      expect(detail[:type]).to eq('has_many')
      expect(detail[:class_name]).to eq('Post')
      expect(detail[:foreign_key]).to eq('user_id')
      expect(detail[:polymorphic]).to be(true)
      expect(detail[:optional]).to be(true)
      expect(detail[:through]).to eq('user_posts')
      expect(detail[:dependent]).to eq('destroy')
    end

    it 'handles associations with empty options gracefully' do
      assoc = double('Association', name: :comments, macro: :has_many, class_name: 'Comment', foreign_key: 'post_id', options: {})
      allow(model).to receive(:reflect_on_all_associations).and_return([assoc])

      result = extractor.call.first
      expect(result[:name]).to eq('comments')
      expect(result).not_to have_key(:polymorphic)
      expect(result).not_to have_key(:through)
    end

    it 'handles multiple associations' do
      assoc1 = double('Association', name: :comments, macro: :has_many, class_name: 'Comment', foreign_key: 'post_id', options: {})
      assoc2 = double('Association', name: :author, macro: :belongs_to, class_name: 'User', foreign_key: 'author_id', options: { optional: true })
      allow(model).to receive(:reflect_on_all_associations).and_return([assoc1, assoc2])

      result = extractor.call
      expect(result.size).to eq(2)
      expect(result.first[:name]).to eq('comments')
      expect(result.last[:name]).to eq('author')
      expect(result.last[:optional]).to be(true)
    end
  end
end
