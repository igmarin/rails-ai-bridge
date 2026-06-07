# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'rails_ai_bridge/registry/skill_source_resolver'

RSpec.describe RailsAiBridge::Registry::SkillSourceResolver do
  let(:cache_dir) { Dir.mktmpdir }
  let(:mock_runner) { instance_double(RailsAiBridge::Registry::GitRunner) }

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe '.default_cache_dir' do
    context 'when RAILS_AI_BRIDGE_CACHE_DIR is set' do
      before do
        ENV['RAILS_AI_BRIDGE_CACHE_DIR'] = '/custom/cache'
      end

      after do
        ENV.delete('RAILS_AI_BRIDGE_CACHE_DIR')
      end

      it 'returns the custom cache directory' do
        result = described_class.default_cache_dir
        expect(result).to eq('/custom/cache')
      end

      it 'handles empty string override' do
        ENV['RAILS_AI_BRIDGE_CACHE_DIR'] = ''
        result = described_class.default_cache_dir
        expected = File.join(Dir.home, '.rails-ai-bridge', 'cache')
        expect(result).to eq(expected)
      end

      it 'handles whitespace-only string' do
        ENV['RAILS_AI_BRIDGE_CACHE_DIR'] = '   '
        result = described_class.default_cache_dir
        expected = File.join(Dir.home, '.rails-ai-bridge', 'cache')
        expect(result).to eq(expected)
      end
    end

    context 'when RAILS_AI_BRIDGE_CACHE_DIR is not set' do
      before do
        ENV.delete('RAILS_AI_BRIDGE_CACHE_DIR')
      end

      it 'returns ~/.rails-ai-bridge/cache' do
        result = described_class.default_cache_dir
        expected = File.join(Dir.home, '.rails-ai-bridge', 'cache')
        expect(result).to eq(expected)
      end
    end
  end

  describe '.compute_cache_key' do
    it 'sanitizes non-alphanumeric characters to underscores' do
      result = described_class.compute_cache_key('igmarin/test-pack')
      expect(result).to match(/^igmarin_test_pack_[a-f0-9]+$/)
    end

    it 'includes a hash suffix' do
      result = described_class.compute_cache_key('test-source')
      expect(result).to match(/_[a-f0-9]+$/)
    end

    it 'produces consistent keys for the same source' do
      key1 = described_class.compute_cache_key('igmarin/ruby-core-skills')
      key2 = described_class.compute_cache_key('igmarin/ruby-core-skills')
      expect(key1).to eq(key2)
    end

    it 'produces different keys for different sources' do
      key1 = described_class.compute_cache_key('igmarin/ruby-core-skills')
      key2 = described_class.compute_cache_key('igmarin/rails-skills')
      expect(key1).not_to eq(key2)
    end

    it 'handles special characters in source' do
      result = described_class.compute_cache_key('user/repo-name.with.dots')
      expect(result).to match(/^user_repo_name_with_dots_[a-f0-9]+$/)
    end

    it 'handles source with only special characters' do
      result = described_class.compute_cache_key('---')
      expect(result).to match(/^____[a-f0-9]+$/)
    end

    it 'handles source with numbers' do
      result = described_class.compute_cache_key('user123/repo456')
      expect(result).to match(/^user123_repo456_[a-f0-9]+$/)
    end

    it 'produces deterministic hash' do
      key1 = described_class.compute_cache_key('test')
      key2 = described_class.compute_cache_key('test')
      expect(key1).to eq(key2)
    end

    it 'hash is different for similar sources' do
      key1 = described_class.compute_cache_key('user/repo')
      key2 = described_class.compute_cache_key('user/repo ')
      expect(key1).not_to eq(key2)
    end
  end

  describe '#initialize' do
    it 'accepts custom git runner' do
      custom_runner = instance_double(RailsAiBridge::Registry::GitRunner)
      resolver = described_class.new(cache_dir, custom_runner)
      expect(resolver.instance_variable_get(:@git_runner)).to eq(custom_runner)
    end

    it 'uses DefaultGitRunner when none provided' do
      resolver = described_class.new(cache_dir)
      expect(resolver.instance_variable_get(:@git_runner)).to be_a(RailsAiBridge::Registry::DefaultGitRunner)
    end

    it 'validates cache directory for path traversal' do
      expect { described_class.new('/tmp/../etc', mock_runner) }
        .to raise_error(ArgumentError, /path traversal/)
    end

    it 'accepts valid cache directory' do
      resolver = described_class.new(cache_dir, mock_runner)
      expect(resolver.instance_variable_get(:@cache_dir)).to eq(cache_dir)
    end
  end

  describe '#resolve' do
    context 'when source format is invalid' do
      it 'raises ResolutionError for invalid format' do
        resolver = described_class.new(cache_dir, mock_runner)
        expect { resolver.resolve('invalid-source') }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /Invalid source format/)
      end

      it 'returns the local path directly for relative traversal sources' do
        # ../relative paths are now treated as valid local path sources by SourceParser.
        # Path traversal security for file content is enforced by the Resolver layer.
        resolver = described_class.new(cache_dir, mock_runner)
        result = resolver.resolve('../etc/passwd')
        expect(result).to eq('../etc/passwd')
      end
    end

    context 'when cache directory does not exist' do
      before do
        allow(mock_runner).to receive_messages(clone_repo: true, pull_repo: true)
      end

      it 'creates the cache directory' do
        non_existent_dir = File.join(cache_dir, 'subdir', 'cache')
        resolver = described_class.new(non_existent_dir, mock_runner)

        allow(mock_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          true
        end

        resolver.resolve('igmarin/test-pack')
        expect(File.exist?(non_existent_dir)).to be true
      end

      it 'creates nested cache directories' do
        nested_dir = File.join(cache_dir, 'a', 'b', 'c')
        resolver = described_class.new(nested_dir, mock_runner)

        allow(mock_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          true
        end

        resolver.resolve('igmarin/test-pack')
        expect(File.exist?(nested_dir)).to be true
      end

      it 'uses correct GitHub URL format' do
        resolver = described_class.new(cache_dir, mock_runner)
        source = 'igmarin/test-pack'
        expected_url = 'https://github.com/igmarin/test-pack.git'

        allow(mock_runner).to receive(:clone_repo) do |url, dest|
          expect(url).to eq(expected_url)
          FileUtils.mkdir_p(dest)
          true
        end

        resolver.resolve(source)
      end
    end

    context 'when cache does not exist' do
      before do
        allow(mock_runner).to receive_messages(clone_repo: true, pull_repo: true)
      end

      it 'clones the repository' do
        resolver = described_class.new(cache_dir, mock_runner)
        source = 'igmarin/test-pack'

        expect(mock_runner).to receive(:clone_repo)
          .with('https://github.com/igmarin/test-pack.git', kind_of(String))
          .and_return(true)

        resolver.resolve(source)
      end

      it 'creates parent directories if needed' do
        resolver = described_class.new(cache_dir, mock_runner)
        source = 'igmarin/test-pack'

        allow(mock_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          true
        end

        path = resolver.resolve(source)
        expect(File.exist?(path)).to be true
      end

      it 'returns the cache path' do
        resolver = described_class.new(cache_dir, mock_runner)
        source = 'igmarin/test-pack'

        allow(mock_runner).to receive(:clone_repo) do |_url, dest|
          FileUtils.mkdir_p(dest)
          true
        end

        path = resolver.resolve(source)
        expect(path).to start_with(cache_dir)
      end

      context 'when clone fails' do
        before do
          allow(mock_runner).to receive(:clone_repo).and_raise(StandardError, 'git clone failed')
        end

        it 'raises ResolutionError' do
          resolver = described_class.new(cache_dir, mock_runner)
          expect { resolver.resolve('igmarin/test-pack') }
            .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /git clone failed/)
        end

        it 'includes source in error message' do
          resolver = described_class.new(cache_dir, mock_runner)
          expect { resolver.resolve('igmarin/test-pack') }
            .to raise_error(%r{igmarin/test-pack})
        end

        it 'cleans up the failed clone directory' do
          resolver = described_class.new(cache_dir, mock_runner)

          allow(mock_runner).to receive(:clone_repo) do |_url, dest|
            FileUtils.mkdir_p(dest)
            raise StandardError, 'git clone failed'
          end

          begin
            resolver.resolve('igmarin/test-pack')
          rescue StandardError
            # Expected
          end

          cache_key = described_class.compute_cache_key('igmarin/test-pack')
          cache_path = File.join(cache_dir, cache_key)
          expect(File.exist?(cache_path)).to be false
        end
      end
    end

    context 'when cache already exists' do
      let(:source) { 'igmarin/test-pack' }
      let(:cache_key) { described_class.compute_cache_key(source) }
      let(:cache_path) { File.join(cache_dir, cache_key) }

      before do
        FileUtils.mkdir_p(cache_path)
        allow(mock_runner).to receive_messages(clone_repo: true, pull_repo: true)
      end

      it 'pulls instead of cloning' do
        resolver = described_class.new(cache_dir, mock_runner)

        expect(mock_runner).to receive(:pull_repo)
          .with(cache_path)
          .and_return(true)

        expect(mock_runner).not_to receive(:clone_repo)

        resolver.resolve(source)
      end

      it 'returns the existing cache path' do
        resolver = described_class.new(cache_dir, mock_runner)
        path = resolver.resolve(source)
        expect(path).to eq(cache_path)
      end

      context 'when pull fails' do
        before do
          allow(mock_runner).to receive(:pull_repo).and_raise(StandardError, 'git pull failed')
        end

        it 'raises an error' do
          resolver = described_class.new(cache_dir, mock_runner)
          expect { resolver.resolve(source) }
            .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /git pull failed/)
        end

        it 'includes source in error message' do
          resolver = described_class.new(cache_dir, mock_runner)
          expect { resolver.resolve(source) }
            .to raise_error(/#{source}/)
        end

        it 'includes original error message' do
          resolver = described_class.new(cache_dir, mock_runner)
          expect { resolver.resolve(source) }
            .to raise_error(/git pull failed/)
        end
      end
    end
  end
end

RSpec.describe RailsAiBridge::Registry::GitRunner do
  describe '#clone_repo' do
    it 'raises NotImplementedError by default' do
      runner = Class.new { include RailsAiBridge::Registry::GitRunner }.new
      expect { runner.clone_repo('url', 'dest') }.to raise_error(NotImplementedError)
    end
  end

  describe '#pull_repo' do
    it 'raises NotImplementedError by default' do
      runner = Class.new { include RailsAiBridge::Registry::GitRunner }.new
      expect { runner.pull_repo('path') }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe RailsAiBridge::Registry::DefaultGitRunner do
  # Open3.capture3 is stubbed throughout this describe block.
  # Real git network calls must never appear in unit tests — they are slow,
  # require internet access, may trigger OS credential dialogs (macOS Keychain),
  # and fail silently in headless CI environments.
  subject(:runner) { described_class.new }

  let(:failing_status) { instance_double(Process::Status, success?: false) }
  let(:succeeding_status) { instance_double(Process::Status, success?: true) }

  describe '#clone_repo' do
    it 'calls git clone with the url and destination' do
      allow(Open3).to receive(:capture3)
        .with('git', 'clone', 'https://github.com/org/repo.git', '/tmp/dest')
        .and_return(['', '', succeeding_status])

      expect { runner.clone_repo('https://github.com/org/repo.git', '/tmp/dest') }.not_to raise_error
    end

    it 'raises RuntimeError when git clone exits non-zero' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'Repository not found.', failing_status])

      expect { runner.clone_repo('https://github.com/org/missing.git', '/tmp/dest') }
        .to raise_error(RuntimeError, /git clone failed: Repository not found\./)
    end

    it 'includes the stderr output in the raised error message' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'fatal: authentication required', failing_status])

      expect { runner.clone_repo('https://example.com/repo.git', '/tmp/dest') }
        .to raise_error(RuntimeError, /authentication required/)
    end
  end

  describe '#pull_repo' do
    it 'calls git pull inside the given directory' do
      allow(Open3).to receive(:capture3)
        .with('git', 'pull', chdir: '/tmp/local-pack')
        .and_return(['Already up to date.', '', succeeding_status])

      expect { runner.pull_repo('/tmp/local-pack') }.not_to raise_error
    end

    it 'raises RuntimeError when git pull exits non-zero' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'error: could not lock config file', failing_status])

      expect { runner.pull_repo('/tmp/local-pack') }
        .to raise_error(RuntimeError, /git pull failed: error: could not lock config file/)
    end

    it 'includes the stderr output in the raised error message' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'CONFLICT (content): Merge conflict in file.rb', failing_status])

      expect { runner.pull_repo('/tmp/local-pack') }
        .to raise_error(RuntimeError, /Merge conflict/)
    end
  end
end
