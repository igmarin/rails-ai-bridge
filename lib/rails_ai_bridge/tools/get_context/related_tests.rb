# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetContext
      # Cheap related-test discovery: +File.exist?+ on conventional spec/test paths.
      # Does not read file bodies or run ripgrep.
      class RelatedTests
        # @param root [Pathname, String, nil] application root
        # @param resolution [Hash] output of {Resolver#call}
        def initialize(root:, resolution:)
          @root = root
          @resolution = resolution
        end

        # @return [Array<String>] relative paths that exist on disk
        def paths
          return [] if @root.nil?

          conventional_paths.select { |relative| File.exist?(File.join(@root.to_s, relative)) }
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

          sources.map { |token| [token.singularize, token.pluralize] }
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
      end
    end
  end
end
