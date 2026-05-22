# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::SearchSemantic do
  around do |example|
    original = RailsAiBridge.configuration.rubydex_enabled
    example.run
  ensure
    RailsAiBridge.configuration.rubydex_enabled = original
    RailsAiBridge::RubydexAdapter.reset!
    RailsAiBridge::RubydexAdapter.reset_availability!
  end

  describe '.call' do
    context 'when rubydex is not available' do
      before do
        RailsAiBridge.configuration.rubydex_enabled = false
      end

      it 'returns unavailability message' do
        response = described_class.call(query: 'User')
        text = response.content.first[:text]
        expect(text).to include('Rubydex semantic analysis is currently disabled')
      end
    end

    context 'when rubydex is enabled but not installed' do
      before do
        RailsAiBridge.configuration.rubydex_enabled = true
        allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(false)
      end

      it 'returns unavailability message' do
        response = described_class.call(query: 'User')
        text = response.content.first[:text]
        expect(text).to include('Rubydex semantic analysis is currently disabled')
      end
    end

    context 'when rubydex is available' do
      let(:mock_adapter) { instance_double(RailsAiBridge::RubydexAdapter) }

      before do
        RailsAiBridge.configuration.rubydex_enabled = true
        allow(RailsAiBridge::RubydexAdapter).to receive_messages(available?: true, instance: mock_adapter)
      end

      it 'performs semantic search and returns formatted results' do
        allow(mock_adapter).to receive(:search)
          .with('User', max_results: 20)
          .and_return([
                        { name: 'User', type: 'class', location: 'app/models/user.rb' },
                        { name: 'UserService', type: 'class', location: 'app/services/user_service.rb' }
                      ])

        response = described_class.call(query: 'User')
        text = response.content.first[:text]
        expect(text).to include("Semantic Search Results for 'User'")
        expect(text).to include('User')
        expect(text).to include('UserService')
        expect(text).to include('[class]')
      end

      it 'returns no results message when nothing found' do
        allow(mock_adapter).to receive(:search)
          .with('NonExistent', max_results: 20)
          .and_return([])

        response = described_class.call(query: 'NonExistent')
        text = response.content.first[:text]
        expect(text).to include("No declarations found matching 'NonExistent'")
      end

      it 'filters by path when provided' do
        allow(mock_adapter).to receive(:file_declarations)
          .with('app/models')
          .and_return([
                        { name: 'User', type: 'class', location: 'app/models/user.rb' },
                        { name: 'Post', type: 'class', location: 'app/models/post.rb' }
                      ])

        response = described_class.call(query: 'User', path: 'app/models')
        text = response.content.first[:text]
        expect(text).to include('User')
        expect(text).not_to include('Post')
      end

      it 'caps max_results' do
        allow(mock_adapter).to receive(:search)
          .with('User', max_results: 50)
          .and_return([])

        described_class.call(query: 'User', max_results: 100)
      end

      it 'normalizes negative max_results to default' do
        allow(mock_adapter).to receive(:search)
          .with('User', max_results: 20)
          .and_return([])

        described_class.call(query: 'User', max_results: -5)
      end
    end
  end

  describe 'tool definition' do
    it 'has correct tool name' do
      expect(described_class.tool_name).to eq('rails_search_semantic')
    end

    it 'has read-only annotations' do
      annotations = described_class.annotations_value
      expect(annotations.read_only_hint).to be(true)
      expect(annotations.destructive_hint).to be(false)
    end

    it 'requires query parameter' do
      schema = described_class.to_h[:inputSchema]
      expect(schema[:required]).to include('query')
    end
  end
end
