# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RailsAiBridge::RubydexAdapter::Indexer do
  let(:indexer) { described_class.new }
  let(:root) { Dir.mktmpdir('indexer_test') }

  before do
    FileUtils.mkdir_p(File.join(root, 'app', 'models'))
    FileUtils.mkdir_p(File.join(root, 'tmp', 'cache'))
    FileUtils.mkdir_p(File.join(root, '.git', 'objects'))
    File.write(File.join(root, 'app', 'models', 'user.rb'), 'class User; end')
    File.write(File.join(root, 'app', 'models', 'post.rb'), 'class Post; end')
    File.write(File.join(root, 'tmp', 'cache', 'cached.rb'), '')
    File.write(File.join(root, '.git', 'objects', 'ignored.rb'), '')
  end

  after do
    FileUtils.rm_rf(root)
  end

  describe '#source_files' do
    it 'returns Ruby files excluding ignored directories' do
      files = indexer.send(:source_files, root).sort

      expected = [
        File.join(root, 'app', 'models', 'user.rb'),
        File.join(root, 'app', 'models', 'post.rb')
      ].sort

      expect(files).to eq(expected)
    end

    it 'excludes tmp, log, vendor, .git, .bundle, node_modules' do
      %w[tmp log vendor .git .bundle node_modules].each do |dir|
        FileUtils.mkdir_p(File.join(root, dir, 'sub'))
        File.write(File.join(root, dir, 'sub', 'excluded.rb'), '')
      end

      files = indexer.send(:source_files, root)
      expect(files).not_to include(match(%r{/tmp/}))
      expect(files).not_to include(match(%r{/log/}))
      expect(files).not_to include(match(%r{/vendor/}))
      expect(files).not_to include(match(%r{/\.git/}))
      expect(files).not_to include(match(%r{/\.bundle/}))
      expect(files).not_to include(match(%r{/node_modules/}))
    end
  end

  describe '#build' do
    before do
      unless defined?(Rubydex)
        Object.const_set(:Rubydex, Module.new)
        Rubydex.const_set(:Graph, Class.new)
      end
    end

    it 'creates a graph, indexes matching files, and resolves' do
      mock_graph = double('graph_instance')
      allow(Rubydex::Graph).to receive(:new).and_return(mock_graph)
      expect(mock_graph).to receive(:index_all).with(kind_of(Array))
      expect(mock_graph).to receive(:resolve)

      graph = indexer.build(root)

      expect(graph).to eq(mock_graph)
    end
  end
end
