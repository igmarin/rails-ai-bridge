# frozen_string_literal: true

require 'open3'
require 'digest'

module RailsAiBridge
  module Registry
    # Interface for git operations, allowing test injection.
    #
    # Implementations should provide methods to clone and pull git repositories.
    #
    # @see DefaultGitRunner
    module GitRunner
      # Clones a remote repository to a local directory path.
      #
      # @param _url [String] git repository URL
      # @param _dest [String] destination directory path
      # @raise [StandardError] if git clone fails
      # @return [void]
      def clone_repo(_url, _dest)
        raise NotImplementedError
      end

      # Pulls latest changes inside a local repository directory.
      #
      # @param _path [String] path to the local repository
      # @raise [StandardError] if git pull fails
      # @return [void]
      def pull_repo(_path)
        raise NotImplementedError
      end

      # Checks out a specific git ref inside a local repository directory.
      #
      # @param _path [String] path to the local repository
      # @param _ref [String] branch, tag, or commit SHA to check out
      # @raise [StandardError] if git checkout fails
      # @return [void]
      def checkout_ref(_path, _ref)
        raise NotImplementedError
      end
    end

    # Default implementation of {GitRunner} using Open3 to spawn git subprocesses.
    #
    # This is the production implementation used for actual git operations.
    # All git commands are wrapped in a +Timeout::timeout+ block so a slow or
    # unreachable remote cannot block the calling thread indefinitely.
    class DefaultGitRunner
      include GitRunner

      # @param timeout [Integer] seconds before a git operation is forcibly interrupted
      attr_reader :timeout

      def initialize(timeout: 30)
        @timeout = timeout
      end

      # Clones a remote repository to a local directory path.
      #
      # @param url [String] git repository URL
      # @param dest [String] destination directory path
      # @raise [RuntimeError] if git clone command fails, returns non-zero, or times out
      # @return [void]
      def clone_repo(url, dest)
        with_timeout('git clone') do
          _stdout, stderr, status = Open3.capture3('git', 'clone', url, dest)
          raise "git clone failed: #{stderr}" unless status.success?
        end
      end

      # Pulls latest changes inside a local repository directory.
      #
      # @param path [String] path to the local repository
      # @raise [RuntimeError] if git pull command fails, returns non-zero, or times out
      # @return [void]
      def pull_repo(path)
        with_timeout('git pull') do
          _stdout, stderr, status = Open3.capture3('git', 'pull', chdir: path)
          raise "git pull failed: #{stderr}" unless status.success?
        end
      end

      # Checks out a specific git ref inside a local repository directory.
      #
      # @param path [String] path to the local repository
      # @param ref [String] branch, tag, or commit SHA to check out
      # @raise [RuntimeError] if git checkout command fails, returns non-zero, or times out
      # @return [void]
      def checkout_ref(path, ref)
        with_timeout('git checkout') do
          _stdout, stderr, status = Open3.capture3('git', 'checkout', ref, chdir: path)
          raise "git checkout failed: #{stderr}" unless status.success?
        end
      end

      private

      def with_timeout(label, &)
        Timeout.timeout(@timeout, &)
      rescue Timeout::Error
        raise "#{label} timed out after #{@timeout}s"
      end
    end

    # Resolves remote git skill pack sources by cloning or pulling them into a local cache directory.
    #
    # Manages a cache of git repositories based on source strings, computing a unique cache key
    # for each source. If the repository is not cached, it clones it; if already cached and the
    # pull TTL window has elapsed, it pulls updates. Otherwise the cached copy is used as-is.
    #
    # @example
    #   resolver = SkillSourceResolver.new('/tmp/cache', DefaultGitRunner.new)
    #   local_path = resolver.resolve('igmarin/ruby-core-skills')
    class SkillSourceResolver
      # Custom error class for resolution failures.
      class ResolutionError < StandardError; end

      # Creates a new SkillSourceResolver with the given cache directory and git runner.
      #
      # @param cache_dir [String] path to the cache directory
      # @param git_runner [GitRunner] git runner implementation (defaults to DefaultGitRunner)
      # @param pull_ttl [Integer] seconds between git pull refreshes per cached pack (default: 86400 = 24 h).
      #   Set to 0 to always pull on every resolve call.
      def initialize(cache_dir, git_runner = DefaultGitRunner.new, pull_ttl: 86_400)
        @cache_dir = validate_cache_dir(cache_dir)
        @git_runner = git_runner
        @pull_ttl = pull_ttl
        @last_pulled = {} # cache_path => Time — in-memory freshness tracking
        @pull_mutex = Mutex.new
      end

      # Resolves the default cache directory, checking RAILS_AI_BRIDGE_CACHE_DIR then HOME.
      #
      # @return [String] path to the default cache directory
      # @raise [RuntimeError] if HOME environment variable is not set or inaccessible
      def self.default_cache_dir
        dir = ENV.fetch('RAILS_AI_BRIDGE_CACHE_DIR', nil)
        return dir if dir && !dir.strip.empty?

        home = Dir.home
        File.join(home, '.rails-ai-bridge', 'cache')
      end

      # Computes a cache key for a given source string and optional ref.
      #
      # When a ref is provided the key includes it so that different refs for the
      # same source produce isolated cache directories, preventing cross-ref
      # contamination. Sanitizes non-alphanumeric characters to underscores and
      # appends a SHA256 hash suffix to ensure uniqueness.
      #
      # @param source [String] source string (e.g., 'igmarin/ruby-core-skills')
      # @param ref [String, nil] git ref or nil for the default branch
      # @return [String] cache key (e.g., 'igmarin_ruby_core_skills_a1b2c3d4')
      def self.compute_cache_key(source, ref = nil)
        identity  = ref ? "#{source}@#{ref}" : source
        sanitized = identity.gsub(/[^a-zA-Z0-9]/, '_')
        hash = Digest::SHA256.hexdigest(identity)[0..15]
        "#{sanitized}_#{hash}"
      end

      # Resolves a source to a local path.
      #
      # Delegates format detection to {SourceParser}. Local paths are returned
      # immediately without any git operations. For git sources:
      #
      # * When +ref+ is nil (floating branch), a pull is attempted if the pack's
      #   TTL window has elapsed, keeping the default branch up-to-date.
      # * When +ref+ is set (pinned tag, SHA, or named branch), the pull is
      #   skipped entirely. A pinned ref is deterministic — there is no reason to
      #   pull, and doing so on a detached HEAD (after checkout) fails with
      #   "You are not currently on a branch".
      #
      # Each (source, ref) pair gets its own cache directory so a repo checked out
      # at two different refs coexists without interference.
      #
      # @param source [String] source string — local path, git URL, or owner/repo shorthand
      # @param ref [String, nil] optional git ref (branch, tag, or SHA) to check out after
      #   cloning; nil means the default branch
      # @return [String] local path to the resolved directory
      # @raise [ResolutionError] if git operations fail or source format is invalid
      def resolve(source, ref: nil)
        parsed = SourceParser.parse(source)
        return parsed.resolved_url if parsed.type == :local_path

        cache_key  = self.class.compute_cache_key(source, ref)
        cache_path = File.join(@cache_dir, cache_key)

        if File.exist?(cache_path)
          # Only pull when no ref is pinned. A pinned ref is deterministic and
          # a previous checkout may have left the repo in detached HEAD, which
          # causes git pull to fail with "not currently on a branch".
          perform_pull(source, cache_path) if ref.nil? && pull_stale?(cache_path)
        else
          perform_clone(source, cache_path, parsed.resolved_url)
        end

        perform_checkout_ref(source, cache_path, ref) if ref
        cache_path
      end

      private

      # Returns true when no successful pull has been recorded for +cache_path+ within
      # the configured pull TTL window. Thread-safe.
      def pull_stale?(cache_path)
        return true if @pull_ttl.zero?

        @pull_mutex.synchronize do
          last = @last_pulled[cache_path]
          last.nil? || (Time.zone.now - last) >= @pull_ttl
        end
      end

      # Records the time of a successful pull for +cache_path+. Thread-safe.
      def record_pull(cache_path)
        @pull_mutex.synchronize { @last_pulled[cache_path] = Time.zone.now }
      end

      # Validates +cache_dir+ by checking that the path does not contain traversal
      # sequences. Uses lexical normalisation only — symlinks are not resolved here
      # because the directory may not exist yet. The security guarantee is that the
      # cache key appended to this dir is SHA-256-derived and not attacker-controlled,
      # so even if cache_dir itself resolves unexpectedly, written paths remain safe.
      def validate_cache_dir(cache_dir)
        clean_path = Pathname.new(cache_dir).cleanpath.to_s
        raise ArgumentError, "Cache directory contains path traversal components: #{cache_dir}" if clean_path != cache_dir

        cache_dir
      end

      def perform_pull(source, cache_path)
        @git_runner.pull_repo(cache_path)
        record_pull(cache_path)
      rescue StandardError => error
        raise ResolutionError, "git pull failed for pack: #{source}: #{error.message}"
      end

      # :reek:TooManyStatements -- Necessary complexity for git clone setup, execution, and error handling
      def perform_clone(source, cache_path, clone_url)
        FileUtils.mkdir_p(@cache_dir)
        @git_runner.clone_repo(clone_url, cache_path)
        record_pull(cache_path)
      rescue StandardError => error
        FileUtils.rm_rf(cache_path)
        raise ResolutionError, "git clone failed for pack: #{source}: #{error.message}"
      end

      def perform_checkout_ref(source, cache_path, ref)
        @git_runner.checkout_ref(cache_path, ref)
      rescue StandardError => error
        raise ResolutionError, "git checkout #{ref} failed for pack: #{source}: #{error.message}"
      end
    end
  end
end
