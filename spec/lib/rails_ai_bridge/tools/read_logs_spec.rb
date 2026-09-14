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

    it 'rejects a symlink inside log/ that points outside the log directory' do
      outside_file = Rails.root.join('config', 'secrets.yml')
      FileUtils.mkdir_p(File.dirname(outside_file))
      File.write(outside_file, "secret: value\n")
      symlink = log_dir.join('escape.log')
      File.symlink(outside_file, symlink)
      expect(text_of(described_class.call(file: 'escape.log'))).to include('error')
    ensure
      FileUtils.rm_f(symlink)
      FileUtils.rm_f(outside_file)
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
      big = log_dir.join('big.log')
      total = described_class::MAX_LINES + 100
      File.write(big, Array.new(total) { |i| "row #{i}" }.join("\n") << "\n")
      payload = JSON.parse(text_of(described_class.call(file: 'big.log', lines: 1_000_000)))
      expect(payload['lines'].size).to eq(described_class::MAX_LINES)
      expect(payload['total_lines']).to eq(total)
      expect(payload['lines'].last).to eq("row #{total - 1}")
    ensure
      FileUtils.rm_f(big)
    end
  end

  describe 'credential redaction' do
    it 'redacts credential patterns before returning' do
      expect(text_of(described_class.call(file: 'production.log'))).not_to include('supersecret123')
      expect(text_of(described_class.call(file: 'production.log'))).to include('[redacted]')
    end
  end

  describe 'invalid utf-8 handling' do
    it 'returns a redacted tail when the byte cap splits a multibyte character' do
      wide = log_dir.join('utf8.log')
      line = ('a' * 1_999) + ('é' * 100)
      File.write(wide, "#{line}\nplain tail line\n")
      payload = JSON.parse(text_of(described_class.call(file: 'utf8.log')))
      expect(payload).not_to have_key('error')
      expect(payload['lines'].last).to eq('plain tail line')
    ensure
      FileUtils.rm_f(wide)
    end

    it 'scrubs genuinely invalid bytes instead of raising ArgumentError' do
      invalid = log_dir.join('invalid_utf8.log')
      File.open(invalid, 'wb') do |f|
        f.write("good line\n")
        f.write("\xFF\xFE invalid bytes\n")
        f.write("tail line\n")
      end
      payload = JSON.parse(text_of(described_class.call(file: 'invalid_utf8.log')))
      expect(payload).not_to have_key('error')
      expect(payload['lines']).to include('tail line')
      expect(payload['lines']).to include("\uFFFD\uFFFD invalid bytes")
    ensure
      FileUtils.rm_f(invalid)
    end
  end

  describe 'per-line memory bound' do
    it 'bounds each line to MAX_LINE_BYTES even when the file contains longer lines' do
      long_line = log_dir.join('long_line.log')
      File.open(long_line, 'wb') do |f|
        f.write("short\n")
        f.write('x' * 5000)
        f.write("\n")
        f.write("tail\n")
      end
      payload = JSON.parse(text_of(described_class.call(file: 'long_line.log')))
      expect(payload).not_to have_key('error')
      max_len = payload['lines'].map(&:length).max
      expect(max_len).to be <= described_class::MAX_LINE_BYTES
      expect(payload['lines'].last).to eq('tail')
    ensure
      FileUtils.rm_f(long_line)
    end

    it 'counts long lines as single lines in total_lines, not multiple chunks' do
      long_line = log_dir.join('long_line_count.log')
      File.open(long_line, 'wb') do |f|
        f.write("line1\n")
        f.write('x' * 5000) # 5000 bytes, will be split into 3 chunks
        f.write("\n")
        f.write("line3\n")
      end
      payload = JSON.parse(text_of(described_class.call(file: 'long_line_count.log')))
      expect(payload).not_to have_key('error')
      expect(payload['total_lines']).to eq(3) # 3 actual lines, not 5 chunks
      expect(payload['lines'].size).to eq(3)
    ensure
      FileUtils.rm_f(long_line)
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
    it 'redacts error messages written to the Rails log' do
      formatter = instance_double(described_class::TailFormatter)
      allow(described_class::TailFormatter).to receive(:new).and_return(formatter)
      allow(formatter).to receive(:format).and_raise(StandardError, 'boom token=supersecret123')
      logged = []
      allow(Rails.logger).to receive(:error) { |*args| logged.concat(args) }

      described_class.call(file: 'production.log')

      expect(logged.join("\n")).not_to include('supersecret123')
    end

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
