# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # In-process composite MCP tool: table + model + routes + controller + related tests.
    #
    # Resolves a single model, controller, or feature name against cached
    # introspector snapshots. Does not perform HTTP or call external providers.
    class GetContext < BaseTool
      tool_name 'rails_get_context'
      description 'Get in-process context for one model, controller, or feature: table, model ' \
                  '(associations, validations, tier, confidence tags), matching routes, controller ' \
                  'actions/filters, and cheap related tests. Not an outbound aggregator — uses local ' \
                  'introspector snapshots only. Provide at least one of model, controller, or feature.'

      input_schema(
        properties: {
          model: {
            type: 'string',
            description: "Optional ActiveRecord model class name (e.g. 'User', 'Post')."
          },
          controller: {
            type: 'string',
            description: "Optional controller name (e.g. 'PostsController' or 'posts')."
          },
          feature: {
            type: 'string',
            description: 'Optional loose feature name used to find a related model and controller ' \
                         'when those arguments are omitted (e.g. "posts", "User").'
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'Detail level. summary: counts and a few facts (default). ' \
                         'standard: key lists. full: reuse per-item formatters.'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Returned when +model+, +controller+, and +feature+ are all blank.
      MISSING_INPUT_MESSAGE = 'Provide at least one of `model`, `controller`, or `feature`.'

      # Returns a single markdown payload for the resolved model/controller/feature.
      #
      # @param model [String, nil] ActiveRecord class name
      # @param controller [String, nil] controller class or path name
      # @param feature [String, nil] inflection-normalized name used when model/controller are omitted
      # @param detail [String] +summary+, +standard+, or +full+
      # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
      # @return [MCP::Tool::Response] composite markdown or a setup/not-found message
      def self.call(model: nil, controller: nil, feature: nil, detail: 'summary', _server_context: nil)
        return text_response(MISSING_INPUT_MESSAGE) if blank_name?(model) && blank_name?(controller) && blank_name?(feature)

        snapshots = build_snapshots
        resolution = Resolver.new(
          model: model,
          controller: controller,
          feature: feature,
          snapshots: snapshots,
          config: config
        ).call

        text_response(render(resolution:, snapshots:, detail: detail.to_s))
      end

      # Builds the snapshot hash from enabled introspector sections.
      # @return [Hash{Symbol => Object, nil}]
      def self.build_snapshots
        {
          models: section_if_enabled(:models),
          schema: section_if_enabled(:schema),
          controllers: section_if_enabled(:controllers),
          routes: section_if_enabled(:routes),
          tests: section_if_enabled(:tests)
        }
      end
      private_class_method :build_snapshots

      # Renders a resolution hash to markdown via Composer and RelatedTests.
      # @param resolution [Hash] output of {Resolver#call}
      # @param snapshots [Hash{Symbol => Object, nil}]
      # @param detail [String]
      # @return [String] markdown body
      def self.render(resolution:, snapshots:, detail:)
        Composer.new(
          resolution: resolution,
          snapshots: snapshots,
          detail: detail,
          test_paths: RelatedTests.new(root: app_root, resolution: resolution).paths
        ).call
      end
      private_class_method :render

      # Host application root used for cheap related-test path checks.
      #
      # @return [Pathname, String, nil]
      def self.app_root
        rails_app&.root
      end

      # Fetches a cached section only when it is in {Configuration#effective_introspectors}.
      # Skips disabled domain introspectors under +:regulated+ even if a stale
      # or unfiltered +cached_section+ would still return payload.
      #
      # @param name [Symbol] introspector key
      # @return [Object, nil]
      def self.section_if_enabled(name)
        return nil unless config.effective_introspectors.include?(name)

        cached_section(name)
      end
      private_class_method :section_if_enabled

      # @param value [String, nil]
      # @return [Boolean] +true+ when the argument is nil or whitespace
      def self.blank_name?(value)
        value.nil? || value.to_s.strip.empty?
      end
      private_class_method :blank_name?
    end
  end
end
