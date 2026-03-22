# frozen_string_literal: true

module RailsAiBridge
  # Extracts edit-focused metadata from a single view file.
  class ViewFileAnalyzer
    class << self
      # Reads a single view file under `app/views` and extracts editing hints.
      #
      # @param root [String, Pathname] Rails root path
      # @param relative_path [String] path relative to `app/views`
      # @return [Hash] normalized metadata for the requested view file
      # @raise [SecurityError] when the path escapes `app/views`
      # @raise [Errno::ENOENT] when the file does not exist
      def call(root:, relative_path:)
        views_root = File.expand_path("app/views", root.to_s)
        requested = File.expand_path(relative_path.to_s, views_root)

        unless requested.start_with?("#{views_root}/") || requested == views_root
          raise SecurityError, "Path not allowed: #{relative_path}"
        end

        raise Errno::ENOENT, relative_path unless File.file?(requested)

        content = File.read(requested)
        relative = requested.delete_prefix("#{views_root}/")

        {
          path: relative,
          template_engine: File.extname(relative).delete("."),
          partial: File.basename(relative).start_with?("_"),
          renders: extract_renders(content),
          turbo_frames: extract_turbo_frames(content),
          stimulus_controllers: extract_stimulus_controllers(content),
          stimulus_actions: extract_stimulus_actions(content),
          content: content
        }
      end

      private

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
