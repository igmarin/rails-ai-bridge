# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::ReadLogs do
  let(:log_dir) { Rails.root.join('log') }
  let(:log_file) { log_dir.join('production.log') }

  before do
    FileUtils.mkdir_p(log_dir)
    File.write(log_file, <<~LOG)
      #{"\n" * 200}
      line 201
      line 202
      token=supersecret123 password=hunter2
      last line
    LOG
  end

  after do
    FileUtils.rm_f(log_file)
    FileUtils.rm_f(log_dir.join('traversal.log'))
  end

  def text_of(result)
    result.content.first[:text]
  end

  describe 'path allowlist' do
    it 'rejects traversal outside the log directory' do
      expect(text_of(described_class.call(file: '../config/secrets.yml'))).to include('error')
    end

    it 'rejects absolute paths outside Rails.root' do
      expect(text_of(described_class.call(file: '/etc/passwd'))).to include('error')
    end

    it 'rejects deep traversal that resolves back inside via dot segments' do
      expect(text_of(described_class.call(file: 'log/../../etc/passwd'))).to include('error')
    end

    it 'rejects non-existent log files' do
      expect(text_of(described_class.call(file: 'no_such_file_rails_ai_bridge.log'))).to include('error')
    end

    it 'reads a file directly under the log directory' do
      expect(text_of(described_class.call(file: 'production.log'))).to include('last line')
    end

    it 'reads a nested file that still resolves inside the log directory' do
      nested = log_dir.join('nested')
      FileUtils.mkdir_p(nested)
      File.write(nested.join('app.log'), "nested content\n")
      expect(text_of(described_class.call(file: 'nested/app.log'))).to include('nested content')
    ensure
      FileUtils.rm_rf(nested)
    end
  end

  describe 'tail cap' do
    it 'returns at most the requested number of lines from the end' do
      payload = JSON.parse(text_of(described_class.call(file: 'production.log', lines: 10)))
      expect(payload['lines'].size).to eq(10)
      expect(payload['lines'].last).to eq('last line')
    end

    it 'returns older lines when the requested tail is longer' do
      payload = JSON.parse(text_of(described_class.call(file: 'production.log', lines: 203)))
      expect(payload['lines'].size).to eq(203)
      expect(payload['lines']).to include('line 201', 'line 202')
    end

    it 'caps lines at a hard maximum regardless of request' do
      result = described_class.call(file: 'production.log', lines: 1_000_000)
      expect(text_of(result).lines.size).to be <= described_class::MAX_LINES
    end
  end

  describe 'credential redaction' do
    it 'redacts credential patterns before returning' do
      expect(text_of(described_class.call(file: 'production.log'))).not_to include('supersecret123')
      expect(text_of(described_class.call(file: 'production.log'))).to include('[redacted]')
    end
  end

  describe 'detail levels' do
    it 'summary returns metadata only' do
      result = described_class.call(file: 'production.log', detail: 'summary')
      expect(text_of(result)).to include('production.log')
      expect(text_of(result)).not_to include('last line')
    end

    it 'full returns a larger tail than standard' do
      standard = described_class.call(file: 'production.log', detail: 'standard').content.first[:text]
      full = described_class.call(file: 'production.log', detail: 'full').content.first[:text]
      expect(full).not_to eq(standard)
      expect(full.length).to be > standard.length
    end
  end

  describe 'error contract' do
    it 'returns a JSON payload with an error key for missing files' do
      payload = JSON.parse(text_of(described_class.call(file: 'no_such_file_rails_ai_bridge.log')))
      expect(payload).to have_key('error')
    end
  end

  describe 'annotations' do
    it 'declares destructive: false, read_only: true, idempotent: true' do
      expect(described_class.annotations.destructive_hint).to be(false)
      expect(described_class.annotations.read_only_hint).to be(true)
      expect(described_class.annotations.idempotent_hint).to be(true)
    end
  end
end
