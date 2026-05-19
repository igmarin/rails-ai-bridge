# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ModelSemanticEnrichment do
  let(:dummy_class) do
    Class.new do
      include RailsAiBridge::Introspectors::ModelSemanticEnrichment

      def config
        @config ||= Struct.new(:rubydex_available?).new(true)
      end
    end
  end

  let(:instance) { dummy_class.new }
  let(:model) { double('Model', name: 'User') }
  let(:adapter) { instance_double(RailsAiBridge::RubydexAdapter) }

  before do
    allow(RailsAiBridge::RubydexAdapter).to receive(:instance).and_return(adapter)
  end

  describe '#extract_semantic_data' do
    it 'returns empty hash if rubydex is not available' do
      allow(instance.config).to receive(:rubydex_available?).and_return(false)
      expect(instance.send(:extract_semantic_data, model)).to eq({})
    end

    it 'returns semantic data' do
      decl = { type: 'class', definitions: [1, 2], ancestors: ['ApplicationRecord'], descendants: [] }
      allow(adapter).to receive(:get_declaration).with('User').and_return(decl)
      allow(adapter).to receive(:ancestors).with('User').and_return(['ApplicationRecord'])
      allow(adapter).to receive(:descendants).with('ApplicationRecord').and_return(%w[User Post])
      allow(adapter).to receive(:descendants).with('User').and_return([])

      result = instance.send(:extract_semantic_data, model)
      expect(result[:semantic_summary]).to include('class with 2 definitions', 'inherits from ApplicationRecord')
      expect(result[:similar_models]).to eq(['Post'])
      expect(result[:complexity_score]).to eq(5) # 2*2 + 1 + 0 = 5
    end
  end

  describe '#extract_semantic_summary' do
    it 'returns nil if declaration is not found' do
      allow(adapter).to receive(:get_declaration).with('User').and_return(nil)
      expect(instance.send(:extract_semantic_summary, model)).to be_nil
    end

    it 'handles errors gracefully' do
      allow(adapter).to receive(:get_declaration).and_raise(StandardError)
      expect(instance.send(:extract_semantic_summary, model)).to be_nil
    end

    it 'formats summary with subclasses' do
      decl = { type: 'class', descendants: %w[Admin Guest] }
      allow(adapter).to receive(:get_declaration).with('User').and_return(decl)
      summary = instance.send(:extract_semantic_summary, model)
      expect(summary).to include('2 subclasses')
    end
  end

  describe '#find_similar_models' do
    it 'returns nil if no similar models found' do
      allow(adapter).to receive_messages(ancestors: [], descendants: [])
      expect(instance.send(:find_similar_models, model)).to be_nil
    end

    it 'handles errors gracefully' do
      allow(adapter).to receive(:ancestors).and_raise(StandardError)
      expect(instance.send(:find_similar_models, model)).to be_nil
    end
  end

  describe '#calculate_complexity_score' do
    it 'returns nil if declaration is not found' do
      allow(adapter).to receive(:get_declaration).with('User').and_return(nil)
      expect(instance.send(:calculate_complexity_score, model)).to be_nil
    end

    it 'handles errors gracefully' do
      allow(adapter).to receive(:get_declaration).and_raise(StandardError)
      expect(instance.send(:calculate_complexity_score, model)).to be_nil
    end
  end
end
