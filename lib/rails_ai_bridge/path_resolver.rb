# frozen_string_literal: true

module RailsAiBridge
  # Resolves configured Rails logical paths to filesystem paths without leaking
  # machine-specific absolute paths into generated assistant context.
  class PathResolver
    # Validates user-provided relative paths before filesystem operations.
    class SafeRelativePath
      # @param path [String] caller-provided relative path or glob pattern
      # @param argument_name [String] name used in validation errors
      def initialize(path, argument_name:)
        @path = path
        @argument_name = argument_name
      end

      # @return [String] normalized safe relative path
      # @raise [ArgumentError] when the path is absolute or contains traversal
      def to_s
        raise ArgumentError, "#{@argument_name} must be a safe relative path" if unsafe?

        normalized
      end

      private

      def unsafe?
        normalized.empty? || normalized.start_with?('/') || windows_absolute? || normalized.split('/').include?('..')
      end

      def windows_absolute?
        normalized.match?(%r{\A[A-Za-z]:/})
      end

      def normalized
        @normalized ||= @path.to_s.tr('\\', '/')
      end
    end
    private_constant :SafeRelativePath

    # Joins a base directory and a safe relative file while keeping the result
    # inside the base directory.
    class SafeJoin
      # @param directory [String] absolute base directory
      # @param relative_file [String] validated relative file path
      def initialize(directory, relative_file)
        @directory = directory
        @relative_file = relative_file
      end

      # @return [String] absolute candidate path
      # @raise [ArgumentError] when the joined path escapes the directory
      def to_s
        raise ArgumentError, 'relative_file must stay within the resolved directory' unless candidate.start_with?(directory_prefix)

        candidate
      end

      private

      def candidate
        @candidate ||= File.expand_path(File.join(expanded_directory, @relative_file))
      end

      def directory_prefix
        "#{expanded_directory}#{File::SEPARATOR}"
      end

      def expanded_directory
        @expanded_directory ||= File.expand_path(@directory)
      end
    end
    private_constant :SafeJoin

    # Handles unexpected Rails path registry failures visibly while preserving
    # the resolver's conventional fallback outside development.
    class ConfiguredPathsError
      # @param logical_path [String] Rails path key being resolved
      # @param error [StandardError] failure raised by the path registry
      def initialize(logical_path, error)
        @logical_path = logical_path
        @error = error
      end

      # @return [Array] empty fallback path list
      # @raise [StandardError] re-raises the original error in development
      def fallback
        raise @error if development?

        logger&.error("RailsAiBridge::PathResolver failed to read path #{@logical_path.inspect}: #{@error.class}: #{@error.message}")
        []
      end

      private

      def development?
        environment&.development?
      end

      def environment
        rails.env if defined?(Rails.env)
      end

      def logger
        rails.logger if defined?(Rails.logger)
      end

      def rails
        @rails ||= Object.const_get(:Rails)
      end
    end
    private_constant :ConfiguredPathsError

    # @param app [Rails::Application] host Rails application
    def initialize(app)
      @app = app
      @root = app.root.to_s
    end

    # Resolves directories for a logical Rails path.
    #
    # Configured +app.paths+ entries are preferred. When none are configured,
    # the conventional root-relative directory is returned.
    #
    # @param logical_path [String] Rails path key, such as +"app/models"+
    # @return [Array<String>] absolute directory paths
    def directories_for(logical_path)
      entries = configured_paths_for(logical_path)
      entries = [logical_path] if entries.empty?

      entries.map { |path| File.expand_path(path.to_s, @root) }.uniq
    end

    # Finds files under every directory for a logical Rails path.
    #
    # @param logical_path [String] Rails path key, such as +"app/models"+
    # @param extension [String] file extension without a leading dot
    # @return [Array<String>] absolute file paths
    def files_for(logical_path, extension:)
      glob_for(logical_path, "**/*.#{extension}")
    end

    # Finds files matching a glob under every directory for a logical Rails path.
    #
    # The pattern must be a safe relative glob. Absolute paths and traversal
    # segments are rejected before +Dir.glob+ runs.
    #
    # @param logical_path [String] Rails path key, such as +"app/views"+
    # @param pattern [String] glob pattern relative to each resolved directory
    # @return [Array<String>] absolute file paths
    # @raise [ArgumentError] when +pattern+ is absolute or contains traversal segments
    def glob_for(logical_path, pattern)
      safe_pattern = SafeRelativePath.new(pattern, argument_name: 'pattern').to_s

      directories_for(logical_path).flat_map do |path|
        Dir.exist?(path) ? Dir.glob(File.join(path, safe_pattern)) : []
      end
    end

    # Finds the first existing file under a logical Rails path.
    #
    # @param logical_path [String] Rails path key, such as +"app/models"+
    # @param relative_file [String] file path relative to the resolved directory
    # @return [String, nil] absolute file path when found
    # @raise [ArgumentError] when +relative_file+ is absolute or contains traversal segments
    def existing_file_for(logical_path, relative_file)
      safe_file = SafeRelativePath.new(relative_file, argument_name: 'relative_file').to_s

      directories_for(logical_path).find do |path|
        candidate = SafeJoin.new(path, safe_file).to_s
        return candidate if File.exist?(candidate)
      end
    end

    # Converts an absolute file path under a logical Rails path into a stable
    # logical path for generated context.
    #
    # @param absolute_path [String] filesystem path to map
    # @param logical_path [String] Rails path key, such as +"app/models"+
    # @return [String] logical context path, root-relative path, or basename fallback
    def logical_file_path(absolute_path, logical_path:)
      path = File.expand_path(absolute_path.to_s)
      matching_root = matching_root_for(path, logical_path)

      return logical_path_from_root(path, matching_root, logical_path) if matching_root

      relative_to_root(path)
    end

    private

    def configured_paths_for(logical_path)
      configured_paths = @app.paths[logical_path]
      Array(configured_paths.to_a).flatten.compact
    rescue NoMethodError
      Array(configured_paths).flatten.compact
    rescue StandardError => error
      ConfiguredPathsError.new(logical_path, error).fallback
    end

    def matching_root_for(path, logical_path)
      directories_for(logical_path).sort_by { |dir| -dir.length }.find do |dir|
        path.start_with?("#{File.expand_path(dir)}#{File::SEPARATOR}")
      end
    end

    def logical_path_from_root(path, matching_root, logical_path)
      root_prefix = "#{File.expand_path(matching_root, @root)}#{File::SEPARATOR}"
      File.join(logical_path, path.delete_prefix(root_prefix))
    end

    def relative_to_root(path)
      return root_relative_path(path) if path_within_root?(path)

      File.basename(path)
    end

    def path_within_root?(path)
      path.start_with?(root_prefix)
    end

    def root_relative_path(path)
      path.delete_prefix(root_prefix)
    end

    def root_prefix
      "#{File.expand_path(@root)}#{File::SEPARATOR}"
    end
  end
end
