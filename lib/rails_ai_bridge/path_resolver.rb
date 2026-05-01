# frozen_string_literal: true

module RailsAiBridge
  # Resolves configured Rails logical paths to filesystem paths without leaking
  # machine-specific absolute paths into generated assistant context.
  class PathResolver
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
    # @param logical_path [String] Rails path key, such as +"app/views"+
    # @param pattern [String] glob pattern relative to each resolved directory
    # @return [Array<String>] absolute file paths
    def glob_for(logical_path, pattern)
      directories_for(logical_path).flat_map do |path|
        Dir.exist?(path) ? Dir.glob(File.join(path, pattern)) : []
      end
    end

    # Finds the first existing file under a logical Rails path.
    #
    # @param logical_path [String] Rails path key, such as +"app/models"+
    # @param relative_file [String] file path relative to the resolved directory
    # @return [String, nil] absolute file path when found
    def existing_file_for(logical_path, relative_file)
      directories_for(logical_path).find do |path|
        candidate = File.join(path, relative_file)
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
    rescue StandardError
      []
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
