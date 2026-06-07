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
    end

    # Default implementation of {GitRunner} using Open3 to spawn git subprocesses.
    #
    # This is the production implementation used for actual git operations.
    class DefaultGitRunner
      include GitRunner

      # Clones a remote repository to a local directory path.
      #
      # @param url [String] git repository URL
      # @param dest [String] destination directory path
      # @raise [RuntimeError] if git clone command fails or returns non-zero exit code
      # @return [void]
      def clone_repo(url, dest)
        _stdout, stderr, status = Open3.capture3('git', 'clone', url, dest)
        return if status.success?

        raise "git clone failed: #{stderr}"
      end

      # Pulls latest changes inside a local repository directory.
      #
      # @param path [String] path to the local repository
      # @raise [RuntimeError] if git pull command fails or returns non-zero exit code
      # @return [void]
      def pull_repo(path)
        _stdout, stderr, status = Open3.capture3('git', 'pull', chdir: path)
        return if status.success?

        raise "git pull failed: #{stderr}"
      end
    end

    # Resolves remote git skill pack sources by cloning or pulling them into a local cache directory.
    #
    # Manages a cache of git repositories based on source strings, computing a unique cache key
    # for each source. If the repository is not cached, it clones it; if cached, it pulls updates.
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
      # @raise [ArgumentError] if cache_dir contains path traversal components
      def initialize(cache_dir, git_runner = DefaultGitRunner.new)
        @cache_dir = validate_cache_dir(cache_dir)
        @git_runner = git_runner
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

      # Computes a cache key for a given source string.
      #
      # Sanitizes non-alphanumeric characters to underscores and appends a hash suffix
      # to ensure uniqueness and prevent collisions.
      #
      # @param source [String] source string (e.g., 'igmarin/ruby-core-skills')
      # @return [String] cache key (e.g., 'igmarin_ruby-core-skills_a1b2c3d4')
      def self.compute_cache_key(source)
        sanitized = source.gsub(/[^a-zA-Z0-9]/, '_')
        hash = Digest::SHA256.hexdigest(source)[0..15]
        "#{sanitized}_#{hash}"
      end

      # Resolves a source to a local path.
      #
      # Delegates format detection to {SourceParser}. Local paths are returned
      # immediately without any git operations. For git sources, the repository
      # is cloned if not cached, or pulled if it already exists.
      #
      # @param source [String] source string — local path, git URL, or owner/repo shorthand
      # @param ref [String, nil] optional git ref (branch, tag, or SHA) to check out after
      #   cloning or pulling; nil means the default branch
      # @return [String] local path to the resolved directory
      # @raise [ResolutionError] if git operations fail or source format is invalid
      def resolve(source, ref: nil)
        parsed = SourceParser.parse(source)
        return parsed.resolved_url if parsed.type == :local_path

        cache_key  = self.class.compute_cache_key(source)
        cache_path = File.join(@cache_dir, cache_key)

        if File.exist?(cache_path)
          perform_pull(source, cache_path)
        else
          perform_clone(source, cache_path, parsed.resolved_url)
        end

        checkout_ref(source, cache_path, ref) if ref
        cache_path
      end

      private

      def validate_cache_dir(cache_dir)
        clean_path = Pathname.new(cache_dir).cleanpath.to_s
        raise ArgumentError, "Cache directory contains path traversal components: #{cache_dir}" if clean_path != cache_dir

        cache_dir
      end

      def perform_pull(source, cache_path)
        @git_runner.pull_repo(cache_path)
      rescue StandardError => error
        raise ResolutionError, "git pull failed for pack: #{source}: #{error.message}"
      end

      # :reek:TooManyStatements -- Necessary complexity for git clone setup, execution, and error handling
      def perform_clone(source, cache_path, clone_url)
        FileUtils.mkdir_p(@cache_dir)
        @git_runner.clone_repo(clone_url, cache_path)
      rescue StandardError => error
        FileUtils.rm_rf(cache_path)
        raise ResolutionError, "git clone failed for pack: #{source}: #{error.message}"
      end

      def checkout_ref(source, cache_path, ref)
        _stdout, stderr, status = Open3.capture3('git', 'checkout', ref, chdir: cache_path)
        return if status.success?

        raise ResolutionError, "git checkout #{ref} failed for pack: #{source}: #{stderr}"
      end
    end
  end
end
