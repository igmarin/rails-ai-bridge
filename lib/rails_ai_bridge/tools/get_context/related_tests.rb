# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetContext
      # Cheap related-test discovery: +File.exist?+ on conventional spec/test paths.
      # Does not read file bodies or run ripgrep. Tokens must be +word+/path segments
      # so +feature+ cannot traverse out of the application root.
      class RelatedTests
        # Model/controller tokens interpolated into conventional test paths.
        SAFE_TOKEN = %r{\A\w+(?:/\w+)*\z}

        # @param root [Pathname, String, nil] application root
        # @param resolution [Hash] output of {Resolver#call}
        def initialize(root:, resolution:)
          @root = root
          @resolution = resolution
        end

        # @return [Array<String>] relative paths that exist on disk under +root+
        def paths
          return [] if @root.nil?

          conventional_paths.select { |relative| safe_exist?(relative) }
        end

        private

        def conventional_paths
          tokens = name_tokens
          tokens.flat_map { |singular, plural| paths_for(singular, plural) }.uniq
        end

        def name_tokens
          sources = [
            @resolution[:model_name],
            @resolution[:table_name],
            controller_token,
            @resolution[:requested_feature]
          ].compact.map { |name| name.to_s.underscore.sub(/_controller\z/, '') }.uniq

          sources.filter_map do |token|
            next unless safe_token?(token)

            singular = token.singularize
            plural = token.pluralize
            next unless safe_token?(singular) && safe_token?(plural)

            [singular, plural]
          end
        end

        def controller_token
          name = @resolution[:controller_name]
          return if name.blank?

          name.to_s.underscore.sub(/_controller\z/, '')
        end

        def paths_for(singular, plural)
          [
            "spec/models/#{singular}_spec.rb",
            "spec/requests/#{plural}_spec.rb",
            "spec/requests/#{singular}_spec.rb",
            "spec/controllers/#{plural}_controller_spec.rb",
            "spec/system/#{plural}_spec.rb",
            "spec/features/#{plural}_spec.rb",
            "test/models/#{singular}_test.rb",
            "test/controllers/#{plural}_controller_test.rb",
            "test/integration/#{plural}_test.rb"
          ]
        end

        def safe_token?(token)
          token.present? && token.match?(SAFE_TOKEN)
        end

        def safe_exist?(relative)
          return false if relative.include?('..') || relative.start_with?('/')
          return false unless relative.match?(%r{\A\w+(?:[/.]\w+)*\z})

          root = File.expand_path(@root.to_s)
          full = File.expand_path(relative, root)
          return false unless contained?(full, root)

          File.exist?(full)
        end

        def contained?(full, root)
          full == root || full.start_with?("#{root}#{File::SEPARATOR}")
        end
      end
    end
  end
end
