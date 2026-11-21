# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::CodeIntelligenceIntrospector do
  subject(:introspector) { described_class.new(app) }

  let(:app) { instance_double(Rails::Application, root: root) }
  let(:root) { File.join(Dir.mktmpdir, 'rai-app') }

  around do |example|
    example.run
  ensure
    FileUtils.rm_rf(File.dirname(root))
  end

  before do
    allow(Open3).to receive(:capture3).and_return(["#{'a' * 40}\n", '', success_status])
  end

  def success_status
    instance_double(Process::Status, success?: true)
  end

  def make_codegraph
    FileUtils.mkdir_p(File.join(root, '.codegraph'))
    FileUtils.touch(File.join(root, '.codegraph', 'codegraph.db'))
  end

  def make_graphify(commit: nil)
    FileUtils.mkdir_p(File.join(root, 'graphify-out'))
    FileUtils.touch(File.join(root, 'graphify-out', 'graph.json'))
    return unless commit

    File.write(File.join(root, 'graphify-out', 'GRAPH_REPORT.md'),
               "# Report\n- Built from commit: `#{commit}`\n")
  end
  describe '#call' do
    context 'with no indexes present' do
      it 'reports both absent with nil timestamps and nil staleness' do
        expect(introspector.call).to eq(
          codegraph: { present: false, index_path: '.codegraph/codegraph.db', indexed_at: nil },
          graphify: {
            present: false,
            graph_path: 'graphify-out/graph.json',
            generated_at: nil,
            graph_commit: nil,
            head_commit: 'a' * 40,
            stale: nil
          }
        )
      end
    end

    context 'with both indexes present' do
      before do
        make_codegraph
        make_graphify(commit: 'a' * 40)
      end

      it 'reports presence, mtimes, and a non-stale graph' do
        result = introspector.call

        expect(result[:codegraph][:present]).to be(true)
        expect(result[:codegraph][:indexed_at]).to be_a(Time)
        expect(result[:graphify][:present]).to be(true)
        expect(result[:graphify][:graph_commit]).to eq('a' * 40)
        expect(result[:graphify][:stale]).to be(false)
      end
    end

    context 'when the graph commit differs from HEAD' do
      before do
        make_graphify(commit: 'b' * 40)
      end

      it 'reports stale' do
        expect(introspector.call[:graphify][:stale]).to be(true)
      end
    end

    context 'when the graph report carries a short SHA' do
      before do
        make_graphify(commit: 'f687ac8')
        allow(Open3).to receive(:capture3).and_return(["f687ac8#{'1' * 33}\n", '', success_status])
      end

      it 'matches the 7-char prefix of HEAD' do
        expect(introspector.call[:graphify][:stale]).to be(false)
      end
    end

    context 'when HEAD commit is unknown' do
      before do
        make_graphify(commit: 'a' * 40)
        allow(Open3).to receive(:capture3).and_return(['', 'fatal: not a git repository', failure_status])
      end

      def failure_status
        instance_double(Process::Status, success?: false)
      end

      it 'reports nil staleness and nil head_commit' do
        result = introspector.call[:graphify]

        expect(result[:head_commit]).to be_nil
        expect(result[:stale]).to be_nil
      end
    end

    context 'when the report is unreadable' do
      before do
        make_graphify
        File.write(File.join(root, 'graphify-out', 'GRAPH_REPORT.md'), 'garbage without commit')
      end

      it 'falls back to nil commit and nil staleness' do
        result = introspector.call[:graphify]

        expect(result[:graph_commit]).to be_nil
        expect(result[:stale]).to be_nil
      end
    end
  end

  describe 'error contract' do
    it 'never raises when the app root vanishes' do
      allow(app).to receive(:root).and_return('/nonexistent-root-xyz')

      expect { introspector.call }.not_to raise_error
    end

    it 'returns an error hash on unexpected failure' do
      allow(app).to receive(:root).and_raise(StandardError, 'boom')

      expect(introspector.call).to eq(error: 'boom')
    end
  end
end
