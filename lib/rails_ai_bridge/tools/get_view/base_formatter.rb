# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Base class for GetView formatters, providing common context and filtering logic.
      class BaseFormatter
        # @param context [Hash] The context hash provided by the tool.
        # @param controller [String, nil] The controller filter used.
        # @param partial [String, nil] The partial filter used.
        def initialize(context:, controller: nil, partial: nil)
          @context = context
          @controller = controller
          @partial = partial
        end

        private

        def heading
          return "# Views for #{@controller}" if @controller
          return "# Partials matching #{@partial}" if @partial

          "# Views"
        end

        def filter_view_data
          filtered = base_view_data(@context)
          filtered = apply_controller_filter(filtered, @controller)
          return filtered if filtered[:error]

          filtered = apply_partial_filter(filtered, @partial)
          return filtered if filtered[:error]

          filtered
        end

        def base_view_data(data)
          {
            layouts: Array(data[:layouts]),
            template_engines: Array(data[:template_engines]),
            templates: (data[:templates] || {}).dup,
            shared_partials: Array(data.dig(:partials, :shared)).dup,
            controller_partials: (data.dig(:partials, :per_controller) || {}).dup,
            helpers: Array(data[:helpers]),
            view_components: Array(data[:view_components])
          }
        end

        def apply_controller_filter(filtered, controller)
          return filtered unless controller

          controller_key = controller_key_for(filtered, controller)
          return { error: "Controller views '#{controller}' not found." } unless controller_key

          filtered.merge(
            templates: filtered[:templates].slice(controller_key),
            controller_partials: filtered[:controller_partials].slice(controller_key)
          )
        end

        def controller_key_for(filtered, controller)
          filtered[:templates].keys.find { |name| name.casecmp?(controller) } ||
            filtered[:controller_partials].keys.find { |name| name.casecmp?(controller) }
        end

        def apply_partial_filter(filtered, partial)
          return filtered unless partial

          matcher = normalize_partial_matcher(partial)
          shared_partials = filtered[:shared_partials].select { |name| partial_match?(name, matcher) }
          controller_partials = filter_controller_partials(filtered[:controller_partials], matcher)

          return { error: "Partial '#{partial}' not found." } if shared_partials.empty? && controller_partials.empty?

          filtered.merge(shared_partials: shared_partials, controller_partials: controller_partials)
        end

        def filter_controller_partials(controller_partials, matcher)
          controller_partials.each_with_object({}) do |(name, files), memo|
            matches = files.select { |file| partial_match?(file, matcher) }
            memo[name] = matches if matches.any?
          end
        end

        def normalize_partial_matcher(partial)
          partial.to_s.sub(%r{\A/+}, "").sub(/\A_/, "")
        end

        def partial_match?(name, matcher)
          normalized = name.to_s.sub(/\A_/, "")
          normalized.include?(matcher) || name.include?(matcher)
        end
      end
    end
  end
end
