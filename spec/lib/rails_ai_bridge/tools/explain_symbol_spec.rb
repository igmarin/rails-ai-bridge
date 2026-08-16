# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::ExplainSymbol do
  let(:explorer) { instance_double(RailsAiBridge::Tools::ExplainSymbol::CliExplorer) }

  around do |example|
    described_class.explorer = explorer
    example.run
  ensure
    described_class.reset!
  end

  describe '.call' do
    context 'when the local CodeGraph index is missing' do
      before do
        allow(described_class).to receive(:index_present?).and_return(false)
      end

      it 'returns a setup message and does not invoke the explorer' do
        expect(explorer).not_to receive(:explore)

        text = described_class.call(query: 'User').content.first[:text]

        expect(text).to include('.codegraph/')
        expect(text).to include('codegraph init')
        expect(text).to include('codegraph index')
      end
    end

    context 'when the local CodeGraph index is present' do
      before do
        allow(described_class).to receive(:index_present?).and_return(true)
      end

      it 'returns truncated markdown from the stubbed explorer' do
        allow(explorer).to receive(:explore).with('User#save').and_return("# User#save\n\nPersists the record.")

        text = described_class.call(query: 'User#save').content.first[:text]

        expect(text).to include('# User#save')
        expect(text).to include('Persists the record.')
      end

      it 'accepts symbol as an alias for query' do
        allow(explorer).to receive(:explore).with('GetSchema').and_return('## GetSchema')

        text = described_class.call(symbol: 'GetSchema').content.first[:text]

        expect(text).to include('## GetSchema')
      end

      it 'prefers query when both symbol and query are given' do
        allow(explorer).to receive(:explore).with('preferred').and_return('ok')

        described_class.call(symbol: 'ignored', query: 'preferred')

        expect(explorer).to have_received(:explore).with('preferred')
      end

      it 'returns a helpful message when symbol and query are blank' do
        expect(explorer).not_to receive(:explore)

        text = described_class.call(query: '   ').content.first[:text]

        expect(text).to include('symbol')
        expect(text).to include('query')
      end

      it 'respects max_tool_response_chars' do
        original = RailsAiBridge.configuration.max_tool_response_chars
        RailsAiBridge.configuration.max_tool_response_chars = 80
        allow(explorer).to receive(:explore).and_return('x' * 200)

        text = described_class.call(query: 'User').content.first[:text]

        expect(text).to include('Response truncated')
        expect(text.length).to be <= 80
      ensure
        RailsAiBridge.configuration.max_tool_response_chars = original
      end

      it 'returns a setup message when the explorer command fails' do
        allow(explorer).to receive(:explore)
          .and_raise(RailsAiBridge::Tools::ExplainSymbol::ExploreError, 'exit 1: index unreadable')

        text = described_class.call(query: 'User').content.first[:text]

        expect(text).to include('exit 1: index unreadable')
        expect(text).to include('codegraph init')
        expect(text).to include('codegraph index')
      end
    end
  end

  describe 'tool definition' do
    it 'uses the rails_explain_symbol name' do
      expect(described_class.tool_name).to eq('rails_explain_symbol')
    end

    it 'is read-only and closed-world' do
      annotations = described_class.annotations_value
      expect(annotations.read_only_hint).to be(true)
      expect(annotations.destructive_hint).to be(false)
      expect(annotations.open_world_hint).to be(false)
    end

    it 'accepts symbol or query' do
      properties = described_class.to_h[:inputSchema][:properties]
      expect(properties).to include(:symbol, :query)
    end
  end
end

RSpec.describe RailsAiBridge::Tools::ExplainSymbol::CliExplorer do
  subject(:explorer) { described_class.new(root: '/tmp/app', timeout: 2) }

  describe '#explore' do
    it 'runs codegraph explore locally with array arguments and a timeout' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3) do |*args, **opts|
        expect(args.first).to be_a(Hash)
        expect(args[1..]).to eq(['codegraph', '--no-color', 'explore', '--path', '/tmp/app', '--', 'User'])
        expect(opts[:chdir]).to eq('/tmp/app')
        ['# User', '', status]
      end

      expect(explorer.explore('User')).to eq('# User')
    end

    it 'does not let a flag-like query override --path' do
      status = instance_double(Process::Status, success?: true)
      captured = nil
      allow(Open3).to receive(:capture3) do |*args, **|
        captured = args[1..]
        ['ok', '', status]
      end

      explorer.explore('-p /')

      expect(captured).to eq(['codegraph', '--no-color', 'explore', '--path', '/tmp/app', '--', '-p /'])
      expect(captured).not_to include('/')
      dashdash = captured.index('--')
      expect(dashdash).not_to be_nil
      expect(captured[dashdash + 1]).to eq('-p /')
      expect(captured[0...dashdash]).to include('--path', '/tmp/app')
    end

    it 'treats --path=/tmp as the explore operand after --' do
      status = instance_double(Process::Status, success?: true)
      captured = nil
      allow(Open3).to receive(:capture3) do |*args, **|
        captured = args[1..]
        ['ok', '', status]
      end

      explorer.explore('--path=/tmp')

      expect(captured).to eq(
        ['codegraph', '--no-color', 'explore', '--path', '/tmp/app', '--', '--path=/tmp']
      )
    end

    it 'raises ExploreError when the command fails' do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return(['', 'boom', status])

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /boom/
      )
    end

    it 'raises ExploreError when the CLI is missing' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /codegraph CLI/
      )
    end

    it 'raises ExploreError when the command times out' do
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /timed out/
      )
    end
  end
end
