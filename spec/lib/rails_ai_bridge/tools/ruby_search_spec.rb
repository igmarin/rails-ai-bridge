# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Tools::SearchCode::RubySearch do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { tmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  def write_file(relative_path, content)
    full_path = File.join(tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  def make_searcher(pattern:, search_path: nil, file_type: nil, max_results: 50)
    RailsAiBridge::Tools::SearchCode::RubySearch.new(
      pattern: pattern,
      search_path: search_path || tmpdir,
      file_type: file_type,
      max_results: max_results,
      root: root
    )
  end

  describe '#call' do
    it 'returns results matching the pattern' do
      write_file('app/models/user.rb', "class User < ApplicationRecord\nend\n")
      results = make_searcher(pattern: 'ApplicationRecord').call
      expect(results).not_to be_empty
      expect(results.first[:file]).to include('user.rb')
      expect(results.first[:line_number]).to eq(1)
      expect(results.first[:content]).to include('ApplicationRecord')
    end

    it 'returns an empty array when nothing matches' do
      write_file('app/models/user.rb', "class User; end\n")
      results = make_searcher(pattern: 'ZZZ_IMPOSSIBLE_XYZ').call
      expect(results).to eq([])
    end

    it 'returns an error result for invalid regex' do
      results = make_searcher(pattern: '(unclosed').call
      expect(results.first[:file]).to eq('error')
      expect(results.first[:content]).to include('Invalid pattern')
    end

    it 'prevents ReDoS with a timeout' do
      write_file('app/models/user.rb', "#{'a' * 50_000}b")
      # A regex that exhibits catastrophic backtracking on non-matches
      require 'benchmark'
      elapsed = Benchmark.realtime do
        results = make_searcher(pattern: '^(a+)+$').call
        expect(results).to be_empty
      end
      expect(elapsed).to be < 2.5
    end

    it 'respects max_results limit' do
      # Write 5 files each matching the pattern
      5.times do |i|
        write_file("app/models/model#{i}.rb", "def foo; end\n")
      end
      results = make_searcher(pattern: 'foo', max_results: 3).call
      expect(results.size).to eq(3)
    end

    it 'skips files excluded via configuration' do
      write_file('vendor/secret.rb', "secret_content here\n")
      allow(RailsAiBridge.configuration).to receive(:excluded_paths).and_return(['vendor/'])
      results = make_searcher(pattern: 'secret_content').call
      expect(results).to be_empty
    end

    it 'skips .env files' do
      write_file('.env', "SECRET_KEY=abc\n")
      # We need to make the glob pick up .env files by providing no file_type filter
      # The glob normally uses *.{rb,...} so .env won't match — test skip_file? directly
      processor = RailsAiBridge::Tools::SearchCode::RubySearch::FileProcessor.new(
        /SECRET_KEY/, [], 50, root
      )
      result = processor.process(File.join(tmpdir, '.env'))
      expect(result).to be_nil # skip_file? returns early, no result
    end

    it 'skips files with secret extensions' do
      key_file = write_file('cert.pem', "-----BEGIN CERTIFICATE-----\n")
      processor = RailsAiBridge::Tools::SearchCode::RubySearch::FileProcessor.new(
        /BEGIN/, [], 50, root
      )
      result = processor.process(key_file)
      expect(result).to be_nil
    end

    it 'filters by file_type when specified' do
      write_file('app/models/user.rb', "class User; end\n")
      write_file('app/models/user.js', "const user = {}\n")
      results = make_searcher(pattern: 'user', file_type: 'rb').call
      expect(results.all? { |r| r[:file].end_with?('.rb') }).to be true
    end

    it 'uses case-insensitive matching' do
      write_file('app/models/user.rb', "class User; end\n")
      results = make_searcher(pattern: 'CLASS').call
      expect(results).not_to be_empty
      expect(results.first[:content]).to include('User')
    end

    it 'returns relative file paths (not absolute)' do
      write_file('app/models/user.rb', "class User; end\n")
      results = make_searcher(pattern: 'User').call
      expect(results.first[:file]).not_to start_with('/')
      expect(results.first[:file]).to eq('app/models/user.rb')
    end

    it 'recovers gracefully from unreadable files' do
      path = write_file('app/models/user.rb', "class User; end\n")
      allow(File).to receive(:readlines).with(path).and_raise(Errno::EACCES)
      results = make_searcher(pattern: 'User').call
      expect(results).to be_an(Array)
    end
  end

  describe RailsAiBridge::Tools::SearchCode::RubySearch::FileProcessor do
    let(:results) { [] }

    def processor(pattern, max: 50)
      described_class.new(Regexp.new(pattern), results, max, root)
    end

    it 'skips files matching .env pattern (case-insensitive)' do
      env_file = write_file('.ENV.local', "SECRET=1\n")
      processor('SECRET').process(env_file)
      expect(results).to be_empty
    end

    it 'skips .key files' do
      key = write_file('private.key', "key content\n")
      processor('key').process(key)
      expect(results).to be_empty
    end

    it 'skips .p12 files' do
      p12 = write_file('cert.p12', "binary\n")
      processor('binary').process(p12)
      expect(results).to be_empty
    end

    it 'skips .pfx files' do
      pfx = write_file('cert.pfx', "binary\n")
      processor('binary').process(pfx)
      expect(results).to be_empty
    end

    it 'skips .crt files' do
      crt = write_file('cert.crt', "cert content\n")
      processor('cert').process(crt)
      expect(results).to be_empty
    end

    it 'processes normal ruby files' do
      rb = write_file('app/models/user.rb', "class User; end\n")
      processor('User').process(rb)
      expect(results).not_to be_empty
    end

    it 'returns :full when max_results is reached' do
      rb = write_file('app/models/user.rb', "User\nUser\nUser\n")
      result = processor('User', max: 2).process(rb)
      expect(result).to eq(:full)
      expect(results.size).to eq(2)
    end
  end
end
