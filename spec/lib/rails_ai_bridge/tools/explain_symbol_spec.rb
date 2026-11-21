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

      it 'treats a query with trailing whitespace after content as non-blank but trimmed' do
        allow(explorer).to receive(:explore).with('User').and_return('ok')

        described_class.call(query: "User\t")
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
        expect(text).to include('CodeGraph explore failed: exit 1: index unreadable. Generate a local index')
      end

      it 'returns the failure message without raising when the explorer crashes unexpectedly' do
        logged = []
        allow(Rails.logger).to receive(:error) { |msg| logged << msg }
        allow(explorer).to receive(:explore).and_raise(StandardError, 'exploded')

        text = described_class.call(query: 'User').content.first[:text]

        expect(text).to include('exploded')
        expect(text).to include('CodeGraph explore failed')
        expect(logged[0]).to eq('exploded')
        expect(logged[1].lines.size).to eq(5)
      end

      it 'reads the failure message from #message, not the interpolated object' do
        error = StandardError.new('message text')
        allow(error).to receive_messages(message: 'via message', to_s: 'via to_s')
        allow(explorer).to receive(:explore).and_raise(error)

        text = described_class.call(query: 'User').content.first[:text]

        expect(text).to start_with('CodeGraph explore failed: via message. Generate a local index')
        expect(text).not_to include('via to_s')
      end

      it 'does not log an ExploreError (it is an expected failure)' do
        allow(Rails.logger).to receive(:error)
        allow(explorer).to receive(:explore)
          .and_raise(RailsAiBridge::Tools::ExplainSymbol::ExploreError, 'expected CLI failure')

        described_class.call(query: 'User')

        expect(Rails.logger).not_to have_received(:error)
      end

      it 'tolerates an exception with a nil backtrace when logging' do
        allow(Rails.logger).to receive(:error)
        error = StandardError.new('no trace')
        allow(error).to receive(:backtrace).and_return(nil)
        allow(explorer).to receive(:explore).and_raise(error)

        expect { described_class.call(query: 'User') }.not_to raise_error
      end

      it 'skips logging when Rails.logger is nil' do
        allow(Rails).to receive(:logger).and_return(nil)
        allow(explorer).to receive(:explore).and_raise(StandardError, 'exploded')

        expect { described_class.call(query: 'User') }.not_to raise_error
      end

      it 'trims surrounding whitespace before invoking the explorer' do
        allow(explorer).to receive(:explore).with('User').and_return('ok')

        described_class.call(query: ' User  ')
      end
    end
  end

  describe 'rails_root integration' do
    it 'resolves to Rails.root as a string' do
      expect(described_class.send(:rails_root)).to eq(Rails.root.to_s)
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

    it 'raises ExploreError with the timeout label when the command times out' do
      allow(Open3).to receive(:capture3).and_raise(Timeout::Error)

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /codegraph explore timed out after 2 seconds/
      )
    end
  end
end

RSpec.describe RailsAiBridge::Tools::ExplainSymbol::GraphifyExplorer do
  subject(:explorer) { described_class.new(root: '/tmp/app', timeout: 2) }

  describe '#explore' do
    it 'runs graphify query against the project graph with a budget' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3) do |*args, **opts|
        expect(args.first).to be_a(Hash)
        expect(args[1..]).to eq(
          ['graphify', 'query', 'User', '--graph', '/tmp/app/graphify-out/graph.json', '--budget', '2000']
        )
        expect(opts[:chdir]).to eq('/tmp/app')
        ['# Graphify User', '', status]
      end

      expect(explorer.explore('User')).to eq('# Graphify User')
    end

    it 'uses the default 15s timeout when none is given' do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(['# Graphify User', '', status])
      explorer = described_class.new(root: '/tmp/app')

      expect(explorer.explore('User')).to eq('# Graphify User')
    end

    it 'stringifies a non-string query' do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(['ok', '', status])

      explorer.explore(nil)

      expect(Open3).to have_received(:capture3) do |*args, **|
        expect(args[1..]).to include('graphify', 'query', '', '--graph', '--budget', '2000')
      end
    end

    it 'raises ExploreError when the command fails' do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return(['', 'graph missing', status])

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /graph missing/
      )
    end

    it 'raises ExploreError when the CLI is missing' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { explorer.explore('User') }.to raise_error(
        RailsAiBridge::Tools::ExplainSymbol::ExploreError,
        /graphify CLI/
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

RSpec.describe 'RailsAiBridge::Tools::ExplainSymbol explorer selection' do
  let(:tool_class) { RailsAiBridge::Tools::ExplainSymbol }

  around do |example|
    tool_class.reset!
    example.run
  ensure
    tool_class.reset!
  end

  it 'selects the CodeGraph explorer when .codegraph/ exists' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(true)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(false)

    expect(tool_class.explorer).to be_a(RailsAiBridge::Tools::ExplainSymbol::CliExplorer)
  end

  it 'falls back to the Graphify explorer when only graph.json exists' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(false)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(true)

    expect(tool_class.explorer).to be_a(RailsAiBridge::Tools::ExplainSymbol::GraphifyExplorer)
  end

  it 'builds explorers with the Rails root' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(true)

    explorer = tool_class.explorer
    expect(explorer.instance_variable_get(:@root)).to eq('/tmp/sel-app')
  end

  it 'runs the explorer when only .codegraph/ exists (no graphify index)' do
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(true)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(false)
    explorer_double = instance_double(RailsAiBridge::Tools::ExplainSymbol::CliExplorer)
    allow(explorer_double).to receive(:explore).and_return('from codegraph')
    allow(tool_class).to receive_messages(rails_root: '/tmp/sel-app', explorer: explorer_double)

    text = tool_class.call(query: 'User').content.first[:text]

    expect(text).to eq('from codegraph')
  end

  it 'prefers the CodeGraph explorer when both indexes exist' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(true)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(true)

    expect(tool_class.explorer).to be_a(RailsAiBridge::Tools::ExplainSymbol::CliExplorer)
  end

  it 'treats neither index as absent' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(false)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(false)

    expect(tool_class.index_present?).to be(false)
  end

  it 'treats a graphify index alone as present' do
    allow(tool_class).to receive(:rails_root).and_return('/tmp/sel-app')
    allow(Dir).to receive(:exist?).with('/tmp/sel-app/.codegraph').and_return(false)
    allow(File).to receive(:exist?).with('/tmp/sel-app/graphify-out/graph.json').and_return(true)

    expect(tool_class.index_present?).to be(true)
  end
end
