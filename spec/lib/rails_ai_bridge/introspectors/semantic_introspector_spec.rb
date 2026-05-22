# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::SemanticIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  around do |example|
    original = RailsAiBridge.configuration.rubydex_enabled
    example.run
  ensure
    RailsAiBridge.configuration.rubydex_enabled = original
    RailsAiBridge::RubydexAdapter.reset!
    RailsAiBridge::RubydexAdapter.reset_availability!
  end

  describe '#call' do
    context 'when rubydex is not available' do
      before do
        RailsAiBridge.configuration.rubydex_enabled = false
      end

      it 'returns info message' do
        result = introspector.call
        expect(result[:info]).to include('Rubydex semantic analysis is currently disabled')
      end
    end

    context 'when rubydex is enabled but not installed' do
      before do
        RailsAiBridge.configuration.rubydex_enabled = true
        allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(false)
      end

      it 'returns info message' do
        result = introspector.call
        expect(result[:info]).to include('Rubydex semantic analysis is currently disabled')
      end
    end

    context 'when rubydex is available' do
      let(:mock_adapter) { instance_double(RailsAiBridge::RubydexAdapter) }

      before do
        RailsAiBridge.configuration.rubydex_enabled = true
        allow(RailsAiBridge::RubydexAdapter).to receive_messages(available?: true, instance: mock_adapter)
      end

      it 'returns semantic analysis hash' do
        allow(mock_adapter).to receive_messages(codebase_stats: {
                                                  total_files: 50,
                                                  total_declarations: 100,
                                                  total_classes: 30,
                                                  total_modules: 20,
                                                  total_methods: 150
                                                }, all_declarations: [
                                                  { name: 'User', type: 'class' },
                                                  { name: 'Post', type: 'class' },
                                                  { name: 'Searchable', type: 'module' }
                                                ], descendants: [], ancestors: [], get_declaration: nil)

        result = introspector.call
        expect(result).to have_key(:codebase_stats)
        expect(result).to have_key(:patterns)
        expect(result).to have_key(:relationships)
        expect(result).to have_key(:complexity_hotspots)
        expect(result[:codebase_stats][:total_files]).to eq(50)
      end

      it 'returns error hash on failure' do
        allow(mock_adapter).to receive(:codebase_stats).and_raise(StandardError, 'test error')

        result = introspector.call
        expect(result[:error]).to eq('test error')
      end
    end
  end
end
