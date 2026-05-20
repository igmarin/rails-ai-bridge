# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::RubydexAdapter::IncrementalIndexer do
  let(:root) { Rails.root.to_s }

  describe '#build' do
    it 'delegates to full index on first call' do
      indexer = described_class.new
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(double('Graph'))

      indexer.build(root)

      expect(RailsAiBridge::RubydexAdapter::Indexer).to have_received(:build_index).with(root)
    end

    it 'returns the graph from a full build' do
      mock_graph = double('Graph')
      indexer = described_class.new
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(mock_graph)

      result = indexer.build(root)

      expect(result).to eq(mock_graph)
    end
  end

  describe '#reindex_changed' do
    let(:mock_graph) { double('Graph') }
    let(:indexer) { described_class.new }

    before do
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(mock_graph)
      indexer.build(root)
    end

    context 'when no files have changed' do
      it 'returns the existing graph without rebuilding' do
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([])

        result = indexer.reindex_changed(root)

        expect(result).to eq(mock_graph)
      end
    end

    context 'when a file has been modified' do
      it 'triggers a full rebuild when changes exceed threshold' do
        files = Array.new(10) { |i| File.join(root, "app/models/model_#{i}.rb") }
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return(files)

        # All files are "new" since file_mtimes was populated with build
        # We need to simulate a state where many files changed
        new_graph = double('NewGraph')
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(new_graph)

        result = indexer.reindex_changed(root)

        expect(result).to eq(new_graph)
      end
    end

    context 'when graph is nil (never built)' do
      it 'falls back to full build' do
        fresh_indexer = described_class.new
        new_graph = double('NewGraph')
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(new_graph)

        result = fresh_indexer.reindex_changed(root)

        expect(result).to eq(new_graph)
      end
    end
  end

  describe '#changed_files' do
    let(:indexer) { described_class.new }

    it 'returns empty array before first build' do
      expect(indexer.changed_files(root)).to eq([])
    end

    it 'detects new files after initial build' do
      mock_graph = double('Graph')
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(mock_graph)
      indexer.build(root)

      existing_files = RailsAiBridge::RubydexAdapter::Indexer.source_files(root)
      new_file = File.join(root, 'app/models/new_model.rb')
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return(existing_files + [new_file])
      allow(File).to receive(:mtime).and_call_original
      allow(File).to receive(:mtime).with(new_file).and_return(Time.now + 60)

      changed = indexer.changed_files(root)

      expect(changed).to include(new_file)
    end
  end

  describe '#full_rebuild_threshold' do
    it 'defaults to 0.3 (30%)' do
      indexer = described_class.new
      expect(indexer.full_rebuild_threshold).to eq(0.3)
    end

    it 'is configurable' do
      indexer = described_class.new(full_rebuild_threshold: 0.5)
      expect(indexer.full_rebuild_threshold).to eq(0.5)
    end
  end
end
