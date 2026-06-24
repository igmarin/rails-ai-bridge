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

    it 'never contains a forward slash' do
      samples = [
        'owner/repo',
        'https://github.com/org/pack.git',
        'git@github.com:org/pack.git',
        '/absolute/local/path'
      ]
      samples.each do |source|
        expect(described_class.compute_cache_key(source)).not_to include('/')
      end
    end

    it 'never contains dot-dot sequences' do
      samples = ['../evil', 'owner/../repo', 'owner/repo/../../../etc']
      samples.each do |source|
        expect(described_class.compute_cache_key(source)).not_to include('..')
      end
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

    # ── R3: symlink guard ─────────────────────────────────────────────────────

    context 'when cache_dir is a symlink to a different real path' do
      let(:real_dir)    { Dir.mktmpdir }
      let(:symlink_dir) { File.join(Dir.mktmpdir, 'link') }

      before  { FileUtils.ln_s(real_dir, symlink_dir) }
      after   { FileUtils.rm_rf([real_dir, File.dirname(symlink_dir)]) }

      it 'raises ArgumentError identifying the symlink' do
        expect { described_class.new(symlink_dir, mock_runner) }
          .to raise_error(ArgumentError, /symlink/)
      end
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

  describe '#resolve with ref:' do
    let(:source) { 'igmarin/test-pack' }
    let(:resolver) { described_class.new(cache_dir, mock_runner) }

    # Helper: pre-seed a ref-specific cache dir so resolve() skips clone.
    def seed_cache_for_ref(ref)
      key  = described_class.compute_cache_key(source, ref)
      path = File.join(cache_dir, key)
      FileUtils.mkdir_p(path)
      path
    end

    context 'when checkout succeeds' do
      let(:ref) { 'v1.2.3' }
      let(:cache_path) { seed_cache_for_ref(ref) }

      before do
        cache_path # ensure dir is created
        allow(mock_runner).to receive(:checkout_ref)
      end

      it 'returns the cache path without raising' do
        expect(resolver.resolve(source, ref: ref)).to eq(cache_path)
      end

      it 'delegates checkout to the git_runner with the correct ref' do
        expect(mock_runner).to receive(:checkout_ref).with(cache_path, ref)

        resolver.resolve(source, ref: ref)
      end

      it 'does not call pull_repo when ref is pinned (detached HEAD protection)' do
        expect(mock_runner).not_to receive(:pull_repo)

        resolver.resolve(source, ref: ref)
      end
    end

    context 'when checkout fails (non-zero exit)' do
      let(:ref) { 'nonexistent-branch' }
      let(:cache_path) { seed_cache_for_ref(ref) }

      before do
        cache_path # ensure dir is created
        allow(mock_runner).to receive(:checkout_ref)
          .with(cache_path, ref)
          .and_raise(StandardError, "error: pathspec 'nonexistent-branch' did not match any file(s)")
      end

      it 'raises ResolutionError' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError)
      end

      it 'includes the ref name in the error message' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /nonexistent-branch/)
      end

      it 'includes the source pack name in the error message' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, %r{igmarin/test-pack})
      end

      it 'includes the error output in the error message' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /pathspec.*did not match/)
      end
    end

    context 'when checkout times out' do
      let(:ref) { 'slow-branch' }
      let(:cache_path) { seed_cache_for_ref(ref) }

      before do
        cache_path # ensure dir is created
        allow(mock_runner).to receive(:checkout_ref)
          .and_raise(StandardError, 'git checkout timed out after 30s')
      end

      it 'raises ResolutionError with a timeout message' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /timed out/)
      end

      it 'names the ref in the timeout error' do
        expect { resolver.resolve(source, ref: ref) }
          .to raise_error(RailsAiBridge::Registry::SkillSourceResolver::ResolutionError, /slow-branch/)
      end
    end

    context 'when ref is nil' do
      it 'does not call git checkout at all' do
        # Arrange — cache exists so no clone either
        FileUtils.mkdir_p(File.join(cache_dir, described_class.compute_cache_key(source, nil)))
        allow(mock_runner).to receive(:pull_repo)
        expect(mock_runner).not_to receive(:checkout_ref)

        resolver.resolve(source, ref: nil)
      end
    end

    context 'when two different refs for the same source are resolved' do
      it 'uses distinct cache directories for each ref' do
        key_v1 = described_class.compute_cache_key(source, 'v1.0.0')
        key_v2 = described_class.compute_cache_key(source, 'v2.0.0')

        expect(key_v1).not_to eq(key_v2)
      end
    end
  end

  describe '#resolve pull freshness (git_pull_ttl)' do
    let(:source) { 'igmarin/test-pack' }
    let(:cache_key) { described_class.compute_cache_key(source) }
    let(:cache_path) { File.join(cache_dir, cache_key) }

    before { FileUtils.mkdir_p(cache_path) }

    context 'when pull_ttl is 0 (always pull)' do
      let(:resolver) { described_class.new(cache_dir, mock_runner, pull_ttl: 0) }

      it 'always calls pull_repo on every resolve' do
        # Arrange
        expect(mock_runner).to receive(:pull_repo).twice

        # Act
        resolver.resolve(source)
        resolver.resolve(source)
      end
    end

    context 'when pull_ttl is large (e.g. 86400)' do
      let(:resolver) { described_class.new(cache_dir, mock_runner, pull_ttl: 86_400) }

      it 'calls pull_repo only once across two back-to-back resolves' do
        # Arrange
        expect(mock_runner).to receive(:pull_repo).once

        # Act — second call happens within the TTL window, so no pull
        resolver.resolve(source)
        resolver.resolve(source)
      end
    end

    context 'when pull_ttl has elapsed between resolves' do
      let(:resolver) { described_class.new(cache_dir, mock_runner, pull_ttl: 86_400) }

      it 'calls pull_repo again after the TTL window expires' do
        # Arrange
        allow(mock_runner).to receive(:pull_repo)

        # Act — first resolve populates @last_pulled
        resolver.resolve(source)

        # Simulate TTL expiry by backdating the recorded pull time
        past_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 90_000
        resolver.instance_variable_get(:@last_pulled)[cache_path] = past_time

        # Assert — second resolve after TTL should pull again
        expect(mock_runner).to receive(:pull_repo).once
        resolver.resolve(source)
      end
    end

    # ── R6: @last_pulled bounded growth ───────────────────────────────────────

    context 'when more than PULL_TRACKER_MAX distinct paths are recorded' do
      let(:resolver) { described_class.new(cache_dir, mock_runner, pull_ttl: 86_400) }

      it 'keeps the tracker at or below PULL_TRACKER_MAX entries' do
        max = described_class::PULL_TRACKER_MAX
        last_pulled = resolver.instance_variable_get(:@last_pulled)

        # Pre-fill the tracker to its limit with fake paths
        max.times { |i| last_pulled["#{cache_dir}/fake_path_#{i}"] = 1.0 }
        expect(last_pulled.size).to eq(max)

        # Recording one more entry should evict the oldest to stay bounded
        resolver.send(:record_pull, "#{cache_dir}/new_path")
        expect(last_pulled.size).to eq(max)
      end

      it 'does not evict when updating an existing entry' do
        max = described_class::PULL_TRACKER_MAX
        last_pulled = resolver.instance_variable_get(:@last_pulled)

        (max - 1).times { |i| last_pulled["#{cache_dir}/fake_path_#{i}"] = 1.0 }
        last_pulled[cache_path] = 1.0
        expect(last_pulled.size).to eq(max)

        # Updating an existing key must not evict anything
        resolver.send(:record_pull, cache_path)
        expect(last_pulled.size).to eq(max)
      end
    end
  end
end

RSpec.describe RailsAiBridge::Registry::GitRunner do
  subject(:runner) { Class.new { include RailsAiBridge::Registry::GitRunner }.new }

  describe '#clone_repo' do
    it 'raises NotImplementedError by default' do
      expect { runner.clone_repo('url', 'dest') }.to raise_error(NotImplementedError)
    end
  end

  describe '#pull_repo' do
    it 'raises NotImplementedError by default' do
      expect { runner.pull_repo('path') }.to raise_error(NotImplementedError)
    end
  end

  describe '#checkout_ref' do
    it 'raises NotImplementedError by default' do
      expect { runner.checkout_ref('path', 'v1.0.0') }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe RailsAiBridge::Registry::DefaultGitRunner do
  # Open3.capture3 is stubbed throughout this describe block.
  # Real git network calls must never appear in unit tests — they are slow,
  # require internet access, may trigger OS credential dialogs (macOS Keychain),
  # and fail silently in headless CI environments.
  subject(:runner) { described_class.new }

  let(:succeeding_status) { instance_double(Process::Status, success?: true) }
  let(:failing_status) { instance_double(Process::Status, success?: false) }

  describe '#timeout' do
    it 'defaults to 30 seconds' do
      # Assert
      expect(runner.timeout).to eq(30)
    end

    it 'is configurable via constructor' do
      # Arrange + Act
      fast_runner = described_class.new(timeout: 5)

      # Assert
      expect(fast_runner.timeout).to eq(5)
    end
  end

  describe 'timeout enforcement' do
    subject(:runner) { described_class.new(timeout: 1) }

    context 'when git clone times out' do
      before { allow(Open3).to receive(:capture3) { sleep(5) } }

      it 'raises RuntimeError mentioning the timeout duration' do
        # Act + Assert
        expect { runner.clone_repo('https://example.com/repo.git', '/tmp/dest') }
          .to raise_error(RuntimeError, /timed out after 1s/)
      end
    end

    context 'when git pull times out' do
      before { allow(Open3).to receive(:capture3) { sleep(5) } }

      it 'raises RuntimeError mentioning the timeout duration' do
        # Act + Assert
        expect { runner.pull_repo('/tmp/local-pack') }
          .to raise_error(RuntimeError, /timed out after 1s/)
      end
    end

    context 'when git checkout times out' do
      before { allow(Open3).to receive(:capture3) { sleep(5) } }

      it 'raises RuntimeError mentioning the timeout duration' do
        # Act + Assert
        expect { runner.checkout_ref('/tmp/local-pack', 'v1.0.0') }
          .to raise_error(RuntimeError, /timed out after 1s/)
      end
    end
  end

  describe '#checkout_ref' do
    it 'calls git checkout with the ref and chdir option' do
      allow(Open3).to receive(:capture3)
        .with('git', 'checkout', 'v1.2.3', chdir: '/tmp/pack')
        .and_return(['', '', succeeding_status])

      expect { runner.checkout_ref('/tmp/pack', 'v1.2.3') }.not_to raise_error
    end

    it 'raises RuntimeError when git checkout exits non-zero' do
      allow(Open3).to receive(:capture3)
        .with('git', 'checkout', 'bad-ref', chdir: '/tmp/pack')
        .and_return(['', 'error: pathspec did not match', failing_status])

      expect { runner.checkout_ref('/tmp/pack', 'bad-ref') }
        .to raise_error(RuntimeError, 'git checkout failed')
    end

    it 'does not embed raw stderr in the error message' do
      allow(Open3).to receive(:capture3)
        .with('git', 'checkout', 'bad-ref', chdir: '/tmp/pack')
        .and_return(['', 'error: pathspec did not match', failing_status])

      expect { runner.checkout_ref('/tmp/pack', 'bad-ref') }
        .to raise_error(RuntimeError) { |e| expect(e.message).not_to include('pathspec') }
    end

    # ── S1: ref option injection guard ────────────────────────────────────────

    context 'when ref starts with a dash (potential git option injection)' do
      it 'raises ArgumentError before invoking git' do
        expect(Open3).not_to receive(:capture3)

        expect { runner.checkout_ref('/tmp/pack', '--orphan') }
          .to raise_error(ArgumentError, /Invalid ref/)
      end

      it 'also blocks single-dash flags' do
        expect(Open3).not_to receive(:capture3)

        expect { runner.checkout_ref('/tmp/pack', '-b') }
          .to raise_error(ArgumentError, /Invalid ref/)
      end

      it 'allows valid branch names that do not start with a dash' do
        allow(Open3).to receive(:capture3)
          .with('git', 'checkout', 'main', chdir: '/tmp/pack')
          .and_return(['', '', succeeding_status])

        expect { runner.checkout_ref('/tmp/pack', 'main') }.not_to raise_error
      end

      it 'allows valid SHA refs' do
        allow(Open3).to receive(:capture3)
          .with('git', 'checkout', 'abc1234def5678', chdir: '/tmp/pack')
          .and_return(['', '', succeeding_status])

        expect { runner.checkout_ref('/tmp/pack', 'abc1234def5678') }.not_to raise_error
      end
    end
  end

  describe '#clone_repo' do
    it 'calls git clone with -- separator and the url and destination' do
      allow(Open3).to receive(:capture3)
        .with('git', 'clone', '--', 'https://github.com/org/repo.git', '/tmp/dest')
        .and_return(['', '', succeeding_status])

      expect { runner.clone_repo('https://github.com/org/repo.git', '/tmp/dest') }.not_to raise_error
    end

    it 'raises RuntimeError when git clone exits non-zero' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'Repository not found.', failing_status])

      expect { runner.clone_repo('https://github.com/org/missing.git', '/tmp/dest') }
        .to raise_error(RuntimeError, 'git clone failed')
    end

    it 'does not embed raw stderr in the error message (credential safety)' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'fatal: authentication required for https://token@github.com/org/repo', failing_status])

      expect { runner.clone_repo('https://token@github.com/org/repo.git', '/tmp/dest') }
        .to raise_error(RuntimeError) { |e| expect(e.message).not_to include('token') }
    end

    it 'rejects URLs starting with a dash (option injection)' do
      expect(Open3).not_to receive(:capture3)

      expect { runner.clone_repo('--upload-pack=evil', '/tmp/dest') }
        .to raise_error(ArgumentError, /Invalid git URL/)
    end

    it 'rejects destinations starting with a dash (option injection)' do
      expect(Open3).not_to receive(:capture3)

      expect { runner.clone_repo('https://github.com/org/repo.git', '-evil') }
        .to raise_error(ArgumentError, /Invalid destination/)
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
        .to raise_error(RuntimeError, 'git pull failed')
    end

    it 'does not embed raw stderr in the error message' do
      allow(Open3).to receive(:capture3)
        .and_return(['', 'CONFLICT (content): Merge conflict in file.rb', failing_status])

      expect { runner.pull_repo('/tmp/local-pack') }
        .to raise_error(RuntimeError) { |e| expect(e.message).not_to include('Merge conflict') }
    end
  end
end
