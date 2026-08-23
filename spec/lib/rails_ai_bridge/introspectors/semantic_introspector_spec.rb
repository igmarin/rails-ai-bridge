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

      context 'with empty declarations' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 0, total_declarations: 0 },
            all_declarations: [],
            descendants: [],
            ancestors: [],
            get_declaration: nil
          )
        end

        it 'returns empty patterns, relationships, and hotspots' do
          result = introspector.call
          expect(result[:patterns]).to eq({})
          expect(result[:relationships]).to eq({})
          expect(result[:complexity_hotspots]).to eq([])
        end
      end

      context 'with class name patterns' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 10 },
            all_declarations: [
              { name: 'UserService', type: 'class' },
              { name: 'SignupForm', type: 'class' },
              { name: 'UserQuery', type: 'class' },
              { name: 'UserPresenter', type: 'class' },
              { name: 'PostDecorator', type: 'class' },
              { name: 'UserSerializer', type: 'class' },
              { name: 'PostPolicy', type: 'class' },
              { name: 'EmailValidator', type: 'class' },
              { name: 'UserObserver', type: 'class' },
              { name: 'SignupInteractor', type: 'class' },
              { name: 'CreateUserCommand', type: 'class' },
              { name: 'ProcessJob', type: 'class' },
              { name: 'WelcomeMailer', type: 'class' },
              { name: 'AuditableConcern', type: 'module' }
            ],
            descendants: [],
            ancestors: ['Object'],
            get_declaration: nil
          )
        end

        it 'detects all naming patterns and concerns' do
          result = introspector.call
          patterns = result[:patterns][:common_patterns]
          expect(patterns).to include('service_objects')
          expect(patterns).to include('form_objects')
          expect(patterns).to include('query_objects')
          expect(patterns).to include('presenters')
          expect(patterns).to include('serializers')
          expect(patterns).to include('policies')
          expect(patterns).to include('validators')
          expect(patterns).to include('observers')
          expect(patterns).to include('interactors')
          expect(patterns).to include('commands')
          expect(patterns).to include('jobs')
          expect(patterns).to include('mailers')
          expect(patterns).to include('concerns(1)')
        end

        it 'computes namespace distribution' do
          result = introspector.call
          expect(result[:patterns][:namespace_distribution]).to be_a(Hash)
        end
      end

      context 'with inheritance relationships' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 5 },
            all_declarations: [
              { name: 'Animal', type: 'class' },
              { name: 'Dog', type: 'class' },
              { name: 'Cat', type: 'class' },
              { name: 'Lonely', type: 'class' }
            ],
            get_declaration: nil
          )
        end

        it 'builds inheritance tree for classes with descendants' do
          allow(mock_adapter).to receive(:descendants) do |name|
            case name
            when 'Animal' then %w[Dog Cat]
            else []
            end
          end
          allow(mock_adapter).to receive(:ancestors) do |name|
            case name
            when 'Lonely' then ['Object']
            else ['Animal']
            end
          end

          result = introspector.call
          tree = result[:relationships][:inheritance_tree]
          expect(tree['Animal']).to eq(%w[Dog Cat])

          most_extended = result[:relationships][:most_extended]
          expect(most_extended.first[:name]).to eq('Animal')

          orphans = result[:relationships][:orphan_classes]
          expect(orphans).to eq(3) # Dog, Cat, Lonely
        end
      end

      context 'with complexity hotspots' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 3 },
            all_declarations: [
              { name: 'HotClass', type: 'class' },
              { name: 'ColdClass', type: 'class' },
              { name: 'NilDetailClass', type: 'class' }
            ],
            descendants: [],
            ancestors: []
          )
        end

        it 'includes hotspots with score >= 5 and skips low-score and nil-detail' do
          allow(mock_adapter).to receive(:get_declaration) do |name|
            case name
            when 'HotClass'
              { definitions: [1, 2, 3], ancestors: %w[A B], descendants: %w[X Y] }
            when 'ColdClass'
              { definitions: [1], ancestors: [], descendants: [] }
            else
              nil
            end
          end

          result = introspector.call
          hotspots = result[:complexity_hotspots]
          names = hotspots.map { |h| h[:name] }
          expect(names).to include('HotClass')
          expect(names).not_to include('ColdClass')
          expect(names).not_to include('NilDetailClass')
        end
      end

      context 'with hotspot detail having nil definitions, ancestors, descendants' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 1 },
            all_declarations: [{ name: 'BigClass', type: 'class' }],
            descendants: [],
            ancestors: []
          )
          allow(mock_adapter).to receive(:get_declaration).and_return({ definitions: nil, ancestors: nil, descendants: nil })
        end

        it 'handles nil fields in hotspot score calculation' do
          result = introspector.call
          # score = 0*2 + 0 + 0*3 = 0, which is < 5, so hotspot is skipped
          expect(result[:complexity_hotspots]).to eq([])
        end
      end

      context 'with namespaced declarations' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 2 },
            all_declarations: [
              { name: 'Admin::UserController', type: 'class' },
              { name: 'Admin::PostController', type: 'class' },
              { name: 'Api::V1::BaseController', type: 'class' }
            ],
            descendants: [],
            ancestors: [],
            get_declaration: nil
          )
        end

        it 'groups namespace distribution by top-level namespace' do
          result = introspector.call
          ns = result[:patterns][:namespace_distribution]
          expect(ns['Admin']).to eq(2)
          expect(ns['Api']).to eq(1)
        end
      end

      context 'with hotspot score exactly 5' do
        before do
          allow(mock_adapter).to receive_messages(
            codebase_stats: { total_files: 1 },
            all_declarations: [{ name: 'Borderline', type: 'class' }],
            descendants: [],
            ancestors: []
          )
          # score = 2*2 + 1 + 0*3 = 5
          allow(mock_adapter).to receive(:get_declaration).and_return(
            { definitions: [1, 2], ancestors: %w[Object], descendants: [] }
          )
        end

        it 'includes hotspot when score is exactly 5' do
          result = introspector.call
          expect(result[:complexity_hotspots].first[:name]).to eq('Borderline')
          expect(result[:complexity_hotspots].first[:complexity_score]).to eq(5)
        end
      end
    end
  end
end
