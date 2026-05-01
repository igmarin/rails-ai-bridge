# frozen_string_literal: true

module RailsAiBridge
  # Extracts edit-focused metadata from a single view file.
  class ViewFileAnalyzer
    class << self
      # Reads a single view file under `app/views` and extracts editing hints.
      #
      # @param root [String, Pathname] Rails root path
      # @param app [Rails::Application, nil] optional app used to resolve configured +app/views+ paths
      # @param relative_path [String] path relative to `app/views`
      # @return [Hash] normalized metadata for the requested view file
      # @raise [SecurityError] when the path escapes `app/views`
      # @raise [Errno::ENOENT] when the file does not exist
      def call(root:, relative_path:, app: nil)
        context = ViewContext.new(root:, app:)
        view_file = resolve_view_file(context, relative_path)
        relative = view_file.relative_path

        content = File.read(view_file.path)

        {
          path: relative,
          template_engine: File.extname(relative).delete('.'),
          partial: File.basename(relative).start_with?('_'),
          renders: extract_renders(content),
          turbo_frames: extract_turbo_frames(content),
          stimulus_controllers: extract_stimulus_controllers(content),
          stimulus_actions: extract_stimulus_actions(content),
          content: content
        }
      end

      private

      # Resolved view file path plus its logical path below +app/views+.
      ViewFile = Struct.new(:path, :relative_path, keyword_init: true)
      private_constant :ViewFile

      # Root and optional Rails app used while resolving configured view paths.
      ViewContext = Struct.new(:root, :app, keyword_init: true)
      private_constant :ViewContext

      # Resolves a requested relative view path to an existing allowed file.
      #
      # @param context [ViewContext] root/app path resolution context
      # @param relative_path [String] requested path below logical +app/views+
      # @return [ViewFile] resolved file metadata
      # @raise [SecurityError] when the requested path escapes every allowed view root
      # @raise [Errno::ENOENT] when the requested path is allowed but absent
      def resolve_view_file(context, relative_path)
        candidates = allowed_view_candidates(context, relative_path)
        raise SecurityError, "Path not allowed: #{relative_path}" if candidates.empty?

        existing_file_candidate(candidates, relative_path)
      end

      # Builds allowed candidates for a requested path across all configured view roots.
      #
      # @param context [ViewContext] root/app path resolution context
      # @param relative_path [String] requested path below logical +app/views+
      # @return [Array<ViewFile>] allowed candidate files
      def allowed_view_candidates(context, relative_path)
        view_roots(context).filter_map do |views_root|
          view_file_candidate(views_root, relative_path)
        end
      end

      # Selects the first candidate that exists on disk.
      #
      # @param candidates [Array<ViewFile>] allowed candidate files
      # @param relative_path [String] original requested path for error reporting
      # @return [ViewFile] existing file metadata
      # @raise [Errno::ENOENT] when none of the candidates exist
      def existing_file_candidate(candidates, relative_path)
        requested = candidates.find { |candidate| File.file?(candidate.path) }
        raise Errno::ENOENT, relative_path unless requested

        requested
      end

      # Returns logical view roots from configured Rails paths or the conventional fallback.
      #
      # @param context [ViewContext] root/app path resolution context
      # @return [Array<String>] absolute view root paths
      def view_roots(context)
        return PathResolver.new(context.app).directories_for('app/views') if configured_app_paths?(context)

        [File.expand_path('app/views', context.root.to_s)]
      end

      # Checks whether the optional app can safely provide paths for the requested root.
      #
      # @param context [ViewContext] root/app path resolution context
      # @return [Boolean] true when configured app paths should be used
      def configured_app_paths?(context)
        app = context.app
        return false unless app

        app.root.to_s == context.root.to_s && app.paths
      rescue NoMethodError
        false
      end

      # Builds a candidate view file when a request remains within a view root.
      #
      # @param views_root [String] absolute view root path
      # @param relative_path [String] requested path below logical +app/views+
      # @return [ViewFile, nil] candidate metadata, or nil when the request escapes
      def view_file_candidate(views_root, relative_path)
        expanded_root = File.expand_path(views_root)
        requested = File.expand_path(relative_path.to_s, expanded_root)
        return nil unless requested.start_with?("#{expanded_root}/") || requested == expanded_root

        ViewFile.new(path: requested, relative_path: requested.delete_prefix("#{expanded_root}/"))
      end

      def extract_renders(content)
        direct = content.scan(/render\s*(?:\(?\s*)["']([^"']+)["']/).flatten
        partials = content.scan(/render\s+partial:\s*["']([^"']+)["']/).flatten

        (direct + partials).uniq.sort
      end

      def extract_turbo_frames(content)
        content.scan(/turbo_frame_tag\s+(?:\(?\s*)["']([^"']+)["']/).flatten.uniq.sort
      end

      def extract_stimulus_controllers(content)
        content.scan(/data-controller=["']([^"']+)["']/).flat_map { |match| match.first.split(/\s+/) }.uniq.sort
      end

      def extract_stimulus_actions(content)
        content.scan(/data-action=["']([^"']+)["']/).flat_map { |match| match.first.split(/\s+/) }.uniq.sort
      end
    end
  end
end
