# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::RubydexAdapter do
  let(:root) { Rails.root.to_s }
  let(:adapter) { described_class.new(root) }

  after do
    described_class.reset!
    described_class.reset_availability!
  end

  describe '.available?' do
    it 'returns false when rubydex gem is not installed' do
      described_class.reset_availability!
      allow(described_class).to receive(:require).with('rubydex').and_raise(LoadError)
      expect(described_class.available?).to be(false)
    end

    it 'caches the availability check' do
      described_class.reset_availability!
      allow(described_class).to receive(:require).with('rubydex').and_return(true)
      result1 = described_class.available?
      result2 = described_class.available?
      expect(result1).to eq(result2)
    end
  end

  describe '.instance' do
    it 'returns an adapter instance' do
      allow(described_class).to receive(:available?).and_return(false)
      expect(described_class.instance(root)).to be_a(described_class)
    end

    it 'caches the instance for the same root' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter1 = described_class.instance(root)
      adapter2 = described_class.instance(root)
      expect(adapter1).to equal(adapter2)
    end

    it 'rebuilds instance when root changes' do
      allow(described_class).to receive(:available?).and_return(false)
      adapter1 = described_class.instance('/tmp/root1')
      adapter2 = described_class.instance('/tmp/root2')
      expect(adapter1).not_to equal(adapter2)
    end
  end

  describe '#index!' do
    it 'does nothing if already indexed' do
      adapter.instance_variable_set(:@indexed, true)
      expect(adapter.index!).to be_nil
    end

    it 'does nothing if not available' do
      allow(described_class).to receive(:available?).and_return(false)
      expect(adapter.index!).to be_nil
      expect(adapter.indexed?).to be(false)
    end

    context 'when available' do
      let(:mock_graph) { double('Graph') }
      let(:success_result) do
        RailsAiBridge::Service::Result.new(true, data: { graph: mock_graph, file_mtimes: {} })
      end

      before do
        allow(described_class).to receive(:available?).and_return(true)
        allow(RailsAiBridge::RubydexAdapter::IncrementalIndexer).to receive(:call)
          .with(:build, root: root, threshold: 0.3, persist: false, index_path: anything)
          .and_return(success_result)
      end

      it 'builds the graph successfully' do
        adapter.index!
        expect(adapter.indexed?).to be(true)
        expect(adapter.graph).to eq(mock_graph)
      end

      it 'rescues errors and sets indexed to false' do
        allow(RailsAiBridge::RubydexAdapter::IncrementalIndexer).to receive(:call)
          .and_raise(StandardError, 'Oops')
        adapter.index!
        expect(adapter.indexed?).to be(false)
        expect(adapter.graph).to be_nil
      end
    end
  end

  describe '#reindex!' do
    let(:mock_graph) { double('Graph') }

    it 'does nothing when not indexed' do
      expect(adapter.reindex!).to be_nil
    end

    it 'does nothing when rubydex is not available' do
      adapter.instance_variable_set(:@indexed, true)
      allow(described_class).to receive(:available?).and_return(false)
      expect(adapter.reindex!).to be_nil
    end

    context 'when indexed and available' do
      let(:new_graph) { double('NewGraph') }
      let(:success_result) do
        RailsAiBridge::Service::Result.new(true, data: { graph: new_graph, file_mtimes: {} })
      end
      let(:test_time) { Time.zone.now }

      before do
        allow(described_class).to receive(:available?).and_return(true)
        adapter.instance_variable_set(:@indexed, true)
        adapter.instance_variable_set(:@graph, mock_graph)
        adapter.instance_variable_set(:@file_mtimes, { 'app.rb' => test_time })
      end

      it 'delegates to incremental indexer service' do
        allow(RailsAiBridge::RubydexAdapter::IncrementalIndexer).to receive(:call)
          .with(:reindex, root: root, graph: mock_graph, file_mtimes: { 'app.rb' => test_time },
                          threshold: 0.3, persist: false, index_path: anything)
          .and_return(success_result)

        adapter.reindex!

        expect(adapter.graph).to eq(new_graph)
      end

      it 'rescues errors without raising' do
        allow(RailsAiBridge::RubydexAdapter::IncrementalIndexer).to receive(:call)
          .and_raise(StandardError, 'fail')

        expect { adapter.reindex! }.not_to raise_error
      end
    end
  end

  context 'when fully indexed' do
    let(:mock_graph) { double('Graph') }
    let(:mock_serializer) { instance_double(RailsAiBridge::RubydexAdapter::Serializer) }
    let(:mock_counter) { instance_double(RailsAiBridge::RubydexAdapter::MethodCounter) }

    before do
      adapter.instance_variable_set(:@indexed, true)
      adapter.instance_variable_set(:@graph, mock_graph)
      adapter.instance_variable_set(:@serializer, mock_serializer)
      adapter.instance_variable_set(:@method_counter, mock_counter)
    end

    describe '#search' do
      it 'returns mapped declarations' do
        results = [double('Decl')]
        allow(mock_graph).to receive(:search).with('User').and_return(results)
        allow(mock_serializer).to receive(:declaration_to_hash).and_return({ name: 'User' })

        expect(adapter.search('User')).to eq([{ name: 'User' }])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:search).and_raise(StandardError)
        expect(adapter.search('User')).to eq([])
      end
    end

    describe '#get_declaration' do
      it 'returns detailed declaration hash' do
        decl = double('Decl')
        allow(mock_graph).to receive(:[]).with('User').and_return(decl)
        allow(mock_serializer).to receive(:detailed_declaration_to_hash).with(decl).and_return({ detailed: true })

        expect(adapter.get_declaration('User')).to eq({ detailed: true })
      end

      it 'returns nil if declaration is not found' do
        allow(mock_graph).to receive(:[]).with('User').and_return(nil)
        expect(adapter.get_declaration('User')).to be_nil
      end

      it 'rescues errors and returns nil' do
        allow(mock_graph).to receive(:[]).and_raise(StandardError)
        expect(adapter.get_declaration('User')).to be_nil
      end
    end

    describe '#all_declarations' do
      it 'returns array of mapped declarations' do
        decl = double('Decl')
        allow(mock_graph).to receive(:declarations).and_return([decl])
        allow(mock_serializer).to receive(:declaration_to_hash).with(decl).and_return({ name: 'User' })

        expect(adapter.all_declarations).to eq([{ name: 'User' }])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:declarations).and_raise(StandardError)
        expect(adapter.all_declarations).to eq([])
      end
    end

    describe '#file_declarations' do
      let(:mock_doc) { double('Document', uri: 'app/models/user.rb', definitions: [double('Defn')]) }

      it 'returns definitions from matching document' do
        allow(mock_graph).to receive(:documents).and_return([mock_doc])
        allow(mock_serializer).to receive(:definition_to_hash).and_return({ type: 'class' })

        expect(adapter.file_declarations('user.rb')).to eq([{ type: 'class' }])
      end

      it 'returns empty array if document not found' do
        allow(mock_graph).to receive(:documents).and_return([mock_doc])
        expect(adapter.file_declarations('missing.rb')).to eq([])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:documents).and_raise(StandardError)
        expect(adapter.file_declarations('user.rb')).to eq([])
      end
    end

    describe '#descendants' do
      it 'returns array of descendant names' do
        decl = double('Decl', descendants: [double('Child', name: 'Admin')])
        allow(mock_graph).to receive(:[]).with('User').and_return(decl)

        expect(adapter.descendants('User')).to eq(['Admin'])
      end

      it 'returns empty array if decl does not support descendants' do
        decl = double('Decl')
        allow(mock_graph).to receive(:[]).with('User').and_return(decl)
        expect(adapter.descendants('User')).to eq([])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:[]).and_raise(StandardError)
        expect(adapter.descendants('User')).to eq([])
      end
    end

    describe '#ancestors' do
      it 'returns array of ancestor names' do
        decl = double('Decl', ancestors: [double('Parent', name: 'ApplicationRecord')])
        allow(mock_graph).to receive(:[]).with('User').and_return(decl)

        expect(adapter.ancestors('User')).to eq(['ApplicationRecord'])
      end

      it 'returns empty array if decl does not support ancestors' do
        decl = double('Decl')
        allow(mock_graph).to receive(:[]).with('User').and_return(decl)
        expect(adapter.ancestors('User')).to eq([])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:[]).and_raise(StandardError)
        expect(adapter.ancestors('User')).to eq([])
      end
    end

    describe '#constant_references' do
      it 'returns mapped references' do
        ref = double('Ref', name: 'API_KEY', location: double('Loc'))
        allow(mock_graph).to receive(:constant_references).and_return([ref])
        allow(mock_serializer).to receive(:format_location).and_return('config/api.rb')

        expect(adapter.constant_references).to eq([{ name: 'API_KEY', location: 'config/api.rb' }])
      end

      it 'rescues errors and returns empty array' do
        allow(mock_graph).to receive(:constant_references).and_raise(StandardError)
        expect(adapter.constant_references).to eq([])
      end
    end

    describe '#codebase_stats' do
      it 'returns calculated statistics' do
        doc = double('Document')
        decl_class = double('DeclClass')
        decl_module = double('DeclModule')

        allow(mock_serializer).to receive(:declaration_type).with(decl_class).and_return('class')
        allow(mock_serializer).to receive(:declaration_type).with(decl_module).and_return('module')
        allow(mock_counter).to receive(:count).and_return(5)

        # safe_count methods
        allow(mock_graph).to receive_messages(documents: [doc], declarations: [decl_class, decl_module], constant_references: [1, 2], method_references: [1])

        expect(adapter.codebase_stats).to eq({
                                               total_files: 1,
                                               total_declarations: 2,
                                               total_classes: 1,
                                               total_modules: 1,
                                               total_methods: 5,
                                               total_constant_references: 2,
                                               total_method_references: 1
                                             })
      end

      it 'handles safe_count gracefully' do
        allow(mock_graph).to receive_messages(documents: [], declarations: [])
        allow(mock_counter).to receive(:count).and_return(0)

        # Test safe_count where method does not exist or raises error
        expect(adapter.codebase_stats).to include(
          total_constant_references: 0,
          total_method_references: 0
        )
      end

      it 'rescues errors and returns empty hash' do
        allow(mock_graph).to receive(:declarations).and_raise(StandardError)
        expect(adapter.codebase_stats).to eq({})
      end
    end
  end

  context 'when unindexed fallback cases' do
    describe '#indexed?' do
      it 'returns false when rubydex is not available' do
        allow(described_class).to receive(:available?).and_return(false)
        expect(adapter.indexed?).to be(false)
      end
    end

    describe '#search' do
      it 'returns empty array when not indexed' do
        expect(adapter.search('User')).to eq([])
      end
    end

    describe '#get_declaration' do
      it 'returns nil when not indexed' do
        expect(adapter.get_declaration('User')).to be_nil
      end
    end

    describe '#all_declarations' do
      it 'returns empty array when not indexed' do
        expect(adapter.all_declarations).to eq([])
      end
    end

    describe '#file_declarations' do
      it 'returns empty array when not indexed' do
        expect(adapter.file_declarations('app/models/user.rb')).to eq([])
      end
    end

    describe '#descendants' do
      it 'returns empty array when not indexed' do
        expect(adapter.descendants('User')).to eq([])
      end
    end

    describe '#ancestors' do
      it 'returns empty array when not indexed' do
        expect(adapter.ancestors('User')).to eq([])
      end
    end

    describe '#constant_references' do
      it 'returns empty array when not indexed' do
        expect(adapter.constant_references).to eq([])
      end
    end

    describe '#codebase_stats' do
      it 'returns empty hash when not indexed' do
        expect(adapter.codebase_stats).to eq({})
      end
    end
  end
end
