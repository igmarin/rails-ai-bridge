# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RailsAiBridge::RubydexAdapter::IncrementalIndexer do
  let(:root) { Dir.mktmpdir('incremental_indexer_test') }
  let(:graph) { double('Graph') }
  let(:new_graph) { double('NewGraph') }

  after do
    FileUtils.rm_rf(root)
  end

  describe '.call(:build)' do
    before do
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(graph)
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([])
    end

    it 'delegates to Indexer.build_index' do
      described_class.call(:build, root: root)

      expect(RailsAiBridge::RubydexAdapter::Indexer).to have_received(:build_index).with(root)
    end

    it 'returns a success result with graph and file_mtimes' do
      result = described_class.call(:build, root: root)

      expect(result).to be_success
      expect(result.data[:graph]).to eq(graph)
      expect(result.data[:file_mtimes]).to eq({})
    end

    it 'persists mtimes when persist is enabled' do
      index_path = File.join(root, 'tmp', 'rubydex_index')
      file = File.join(root, 'app', 'models', 'user.rb')
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, 'class User; end')

      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([file])

      result = described_class.call(:build, root: root, persist: true, index_path: index_path)

      expect(result).to be_success
      expect(File.exist?(File.join(index_path, 'mtimes.json'))).to be(true)
    end
  end

  describe '.call(:reindex)' do
    context 'when graph is nil' do
      before do
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(new_graph)
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([])
      end

      it 'falls back to full build' do
        result = described_class.call(:reindex, root: root, graph: nil)

        expect(result).to be_success
        expect(result.data[:graph]).to eq(new_graph)
        expect(RailsAiBridge::RubydexAdapter::Indexer).to have_received(:build_index).with(root)
      end
    end

    context 'when no files have changed' do
      let(:app_file) { File.join(root, 'app.rb') }

      before do
        File.write(app_file, 'class App; end')
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([app_file])
      end

      it 'returns the existing graph and mtimes' do
        file_mtimes = { app_file => File.mtime(app_file).to_r }
        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes)

        expect(result).to be_success
        expect(result.data[:graph]).to eq(graph)
        expect(result.data[:file_mtimes]).to eq(file_mtimes)
      end
    end

    context 'when changes exceed threshold' do
      let(:files) { Array.new(10) { |i| File.join(root, "model_#{i}.rb") } }

      before do
        files.each { |f| File.write(f, "class Model#{f}; end") }
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return(files)
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(new_graph)
      end

      it 'falls back to full rebuild' do
        file_mtimes = { File.join(root, 'old.rb') => (Time.zone.now - 100).to_r }
        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes, threshold: 0.2)

        expect(result).to be_success
        expect(result.data[:graph]).to eq(new_graph)
        expect(RailsAiBridge::RubydexAdapter::Indexer).to have_received(:build_index).with(root)
      end
    end

    context 'when changes are below threshold' do
      let(:changed_file) { File.join(root, 'changed.rb') }
      let(:unchanged_file) { File.join(root, 'unchanged.rb') }
      let(:removed_file) { File.join(root, 'removed.rb') }

      def stable_a
        File.join(root, 'stable_a.rb')
      end

      def stable_b
        File.join(root, 'stable_b.rb')
      end

      before do
        File.write(changed_file, 'class Changed; end')
        File.write(unchanged_file, 'class Unchanged; end')
        File.write(stable_a, 'class StableA; end')
        File.write(stable_b, 'class StableB; end')
        allow(graph).to receive(:respond_to?).with(:delete_document).and_return(true)
        allow(graph).to receive(:respond_to?).with(:index_source).and_return(true)
        allow(graph).to receive(:respond_to?).with(:resolve).and_return(true)
        allow(graph).to receive(:document).with(changed_file).and_return(double('Doc'))
        allow(graph).to receive(:document).with(removed_file).and_return(nil)
        allow(graph).to receive(:delete_document)
        allow(graph).to receive(:index_source)
        allow(graph).to receive(:resolve)
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root)
                                                                               .and_return([changed_file, unchanged_file, stable_a, stable_b])
      end

      it 'applies incremental changes and calls resolve' do
        file_mtimes = {
          changed_file => (Time.zone.now - 100).to_r,
          unchanged_file => File.mtime(unchanged_file).to_r,
          removed_file => (Time.zone.now - 100).to_r,
          stable_a => File.mtime(stable_a).to_r,
          stable_b => File.mtime(stable_b).to_r
        }

        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes, threshold: 0.6)

        expect(result).to be_success
        expect(graph).to have_received(:delete_document).with(changed_file)
        expect(graph).to have_received(:index_source).with(changed_file, 'class Changed; end', 'ruby')
        expect(graph).to have_received(:delete_document).with(removed_file)
        expect(graph).to have_received(:resolve)
        expect(result.data[:graph]).to eq(graph)
      end

      it 'skips index_source when graph does not support it' do
        allow(graph).to receive(:respond_to?).with(:index_source).and_return(false)
        file_mtimes = {
          changed_file => (Time.zone.now - 100).to_r,
          unchanged_file => File.mtime(unchanged_file).to_r,
          stable_a => File.mtime(stable_a).to_r,
          stable_b => File.mtime(stable_b).to_r
        }

        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes, threshold: 0.6)

        expect(result).to be_success
        expect(graph).not_to have_received(:index_source)
      end

      it 'skips delete_document when graph does not support it' do
        allow(graph).to receive(:respond_to?).with(:delete_document).and_return(false)
        file_mtimes = {
          changed_file => (Time.zone.now - 100).to_r,
          unchanged_file => File.mtime(unchanged_file).to_r,
          stable_a => File.mtime(stable_a).to_r,
          stable_b => File.mtime(stable_b).to_r
        }

        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes, threshold: 0.6)

        expect(result).to be_success
        expect(graph).not_to have_received(:delete_document)
      end
    end

    context 'when total file count is zero' do
      before do
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([])
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).with(root).and_return(new_graph)
      end

      it 'does not divide by zero and falls back to build' do
        file_mtimes = { File.join(root, 'old.rb') => Time.zone.now.to_r }
        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: file_mtimes)

        expect(result).to be_success
        expect(result.data[:graph]).to eq(new_graph)
      end
    end

    context 'with persistence' do
      let(:index_path) { File.join(root, 'tmp', 'rubydex_index') }
      let(:file) { File.join(root, 'app.rb') }
      let(:stable_file) { File.join(root, 'stable.rb') }

      before do
        File.write(file, 'class App; end')
        File.write(stable_file, 'class Stable; end')
        allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).with(root).and_return([file, stable_file])
        allow(graph).to receive(:respond_to?).with(:delete_document).and_return(true)
        allow(graph).to receive(:respond_to?).with(:index_source).and_return(true)
        allow(graph).to receive(:respond_to?).with(:resolve).and_return(true)
        allow(graph).to receive(:document).and_return(nil)
        allow(graph).to receive(:delete_document)
        allow(graph).to receive(:index_source)
        allow(graph).to receive(:resolve)
      end

      it 'loads persisted mtimes when file_mtimes is empty' do
        old_mtime = (Time.zone.now - 100).to_r
        FileUtils.mkdir_p(index_path)
        File.write(File.join(index_path, 'mtimes.json'), JSON.dump({ file => old_mtime, stable_file => File.mtime(stable_file).to_r }))

        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: {},
                                                persist: true, index_path: index_path, threshold: 1.0)

        expect(result).to be_success
        expect(graph).to have_received(:index_source).with(file, 'class App; end', 'ruby')
      end

      it 'saves updated mtimes after reindex as rational seconds' do
        old_mtime = (Time.zone.now - 100).to_r
        FileUtils.mkdir_p(index_path)
        File.write(File.join(index_path, 'mtimes.json'), JSON.dump({ file => old_mtime, stable_file => File.mtime(stable_file).to_r }))

        result = described_class.call(:reindex, root: root, graph: graph, file_mtimes: {},
                                                persist: true, index_path: index_path, threshold: 1.0)

        expect(result).to be_success
        persisted = JSON.parse(File.read(File.join(index_path, 'mtimes.json')))
        expect(persisted.keys).to include(file)
        expect(persisted[file]).to eq(File.mtime(file).to_r.to_s)
      end
    end
  end

  describe 'unsupported operation' do
    it 'returns a failure result' do
      result = described_class.call(:invalid, root: root)

      expect(result).to be_failure
      expect(result.errors).to include('Unsupported operation: invalid')
    end
  end

  describe 'error handling' do
    it 'rescues StandardError and returns a failure result' do
      allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:build_index).and_raise(StandardError, 'boom')

      result = described_class.call(:build, root: root)

      expect(result).to be_failure
      expect(result.errors.first).to include('boom')
    end
  end
end
