# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetContext
      # Resolves model, controller, table, and route keys from tool arguments.
      #
      # Feature names are inflection-normalized (underscore, singularize/pluralize,
      # classify, +Controller+ suffix) and matched case-insensitively against
      # cached snapshot keys. Explicit +model+ / +controller+ win over +feature+.
      class Resolver
        # @param model [String, nil]
        # @param controller [String, nil]
        # @param feature [String, nil]
        # @param snapshots [Hash{Symbol => Object}]
        # @param config [RailsAiBridge::Configuration]
        def initialize(model:, controller:, feature:, snapshots:, config:)
          @model = model.to_s.strip.presence
          @controller = controller.to_s.strip.presence
          @feature = feature.to_s.strip.presence
          @snapshots = snapshots
          @config = config
        end

        # @return [Hash] resolved names, payloads, and error/setup messages
        def call
          return explicit_model_error if explicit_model_blocked?

          resolved_model = match_model(@model) || match_model(@feature) || infer_model_from_controller(seed_controller)
          resolved_controller = match_controller(@controller) || match_controller(@feature) ||
                                infer_controller_from_model(resolved_model)
          resolved_model ||= infer_model_from_controller(resolved_controller)
          domain_blocked = related_model_excluded?(resolved_model || resolved_controller || @feature || @controller)

          table_name, table_data = domain_blocked ? [nil, nil] : resolve_table(resolved_model)
          routes = if domain_blocked || excluded_table?(table_name)
                     {}
                   else
                     matching_routes(resolved_controller, resolved_model, table_name)
                   end
          {
            requested_model: @model,
            requested_controller: @controller,
            requested_feature: @feature,
            model_name: resolved_model,
            model_data: model_payload(resolved_model),
            table_name: table_name,
            table_data: table_data,
            schema_source: schema_source,
            controller_name: resolved_controller,
            controller_data: controller_payload(resolved_controller),
            routes: routes,
            setup_messages: setup_messages,
            error: nothing_resolved_error(resolved_model, resolved_controller, table_name)
          }
        end

        private

        def explicit_model_blocked?
          @model && (excluded_model?(@model) || match_model(@model).nil?)
        end

        def explicit_model_error
          {
            requested_model: @model,
            requested_controller: @controller,
            requested_feature: @feature,
            model_name: nil,
            model_data: nil,
            table_name: nil,
            table_data: nil,
            schema_source: schema_source,
            controller_name: nil,
            controller_data: nil,
            routes: {},
            setup_messages: setup_messages,
            error: model_not_found_message(@model)
          }
        end

        def seed_controller
          match_controller(@controller) || match_controller(@feature)
        end

        def models
          data = @snapshots[:models]
          data.is_a?(Hash) && !data[:error] ? data : {}
        end

        def controllers
          data = @snapshots[:controllers]
          return {} unless data.is_a?(Hash) && !data[:error]

          data[:controllers] || {}
        end

        def schema_tables
          data = @snapshots[:schema]
          return {} unless data.is_a?(Hash) && !data[:error]

          data[:tables] || {}
        end

        def routes_by_controller
          data = @snapshots[:routes]
          return {} unless data.is_a?(Hash) && !data[:error]

          data[:by_controller] || {}
        end

        def match_model(name)
          return nil if name.blank? || excluded_model?(name)

          candidates = model_candidates(name)
          key = models.keys.find { |model_key| candidates.any? { |candidate| model_key.to_s.casecmp?(candidate) } }
          return nil if key.nil? || excluded_model?(key)

          key
        end

        def match_controller(name)
          return nil if name.blank?

          candidates = controller_candidates(name)
          key = controllers.keys.find { |ctrl| candidates.any? { |candidate| ctrl.to_s.casecmp?(candidate) } }
          return key if key

          token = normalize(name)
          controllers.keys.find do |ctrl|
            snake = ctrl.to_s.underscore.sub(/_controller\z/, '')
            snake == token || snake.pluralize == token || snake.singularize == token
          end
        end

        def infer_model_from_controller(controller_name)
          return nil if controller_name.blank?

          match_model(normalize(controller_name))
        end

        def infer_controller_from_model(model_name)
          return nil if model_name.blank?

          match_controller(model_name)
        end

        def resolve_table(model_name)
          from_model = model_payload(model_name)&.[](:table_name).presence
          candidates = [from_model, *table_candidates(model_name || @feature || @model || @controller)].compact
          name = candidates.find { |candidate| schema_tables.key?(candidate) && !excluded_table?(candidate) }
          name ||= from_model unless from_model && excluded_table?(from_model)
          return [nil, nil] if name.nil? || excluded_table?(name)

          [name, schema_tables[name]]
        end

        def matching_routes(controller_name, model_name, table_name)
          tokens = [
            controller_route_token(controller_name),
            normalize(model_name),
            normalize(model_name)&.pluralize,
            table_name
          ].compact.uniq

          routes_by_controller.select do |key, _|
            snake = key.to_s.downcase
            next false if excluded_route_key?(snake)

            tokens.any? { |token| snake == token || snake.end_with?("/#{token}") }
          end
        end

        def related_model_excluded?(name)
          return false if name.blank?
          return true if excluded_model?(name)

          model_candidates(name).any? { |candidate| excluded_model?(candidate) }
        end

        def excluded_table?(name)
          return false if name.blank?

          @config.excluded_table?(name)
        end

        def excluded_route_key?(key)
          return true if excluded_table?(key)

          @config.excluded_models.any? do |model|
            token = normalize(model)
            next false if token.blank?

            key == token || key == token.pluralize || key == token.tableize ||
              key.end_with?("/#{token}") || key.end_with?("/#{token.pluralize}")
          end
        end

        def controller_route_token(controller_name)
          return if controller_name.blank?

          controller_name.to_s.underscore.sub(/_controller\z/, '')
        end

        def model_payload(name)
          return if name.nil?

          models[name]
        end

        def controller_payload(name)
          return if name.nil?

          controllers[name]
        end

        def model_candidates(name)
          token = normalize(name)
          [
            name.to_s.strip,
            token.classify,
            token.camelize,
            token.singularize.classify,
            token.pluralize.classify
          ].uniq
        end

        def controller_candidates(name)
          token = normalize(name)
          classified = token.singularize.classify
          [
            name.to_s.strip,
            "#{classified}Controller",
            "#{token.pluralize.camelize}Controller",
            "#{token.camelize}Controller"
          ].uniq
        end

        def table_candidates(name)
          token = normalize(name)
          return [] if token.blank?

          [token.tableize, token.pluralize, token.singularize].uniq
        end

        def normalize(name)
          return if name.blank?

          name.to_s.strip.underscore.sub(/_controller\z/i, '')
        end

        def excluded_model?(name)
          return false if name.blank?

          @config.excluded_models.any? { |entry| entry.to_s.casecmp?(name.to_s.strip) } ||
            @config.excluded_models.any? { |entry| entry.to_s.casecmp?(name.to_s.strip.classify) }
        end

        def schema_source
          schema = @snapshots[:schema]
          return unless schema.is_a?(Hash)

          return schema[:source] if schema.key?(:source)

          adapter = schema[:adapter].to_s
          return :static if adapter == 'static_parse'
          return :live if adapter.present?

          nil
        end

        def setup_messages
          messages = []
          messages << 'Model introspection not available. Add :models to introspectors.' if section_missing?(:models)
          messages << "Model introspection failed: #{@snapshots[:models][:error]}" if section_error?(:models)
          messages << 'Schema introspection not available. Add :schema to introspectors.' if section_missing?(:schema)
          messages << "Schema introspection not available: #{@snapshots[:schema][:error]}" if section_error?(:schema)
          messages
        end

        def section_missing?(key)
          @snapshots[key].nil?
        end

        def section_error?(key)
          data = @snapshots[key]
          data.is_a?(Hash) && data[:error]
        end

        def nothing_resolved_error(model_name, controller_name, table_name)
          return if model_name || controller_name || table_name

          if @model
            model_not_found_message(@model)
          elsif @controller
            "Controller '#{display_name(@controller)}' not found. Available: #{controllers.keys.sort.join(', ')}"
          else
            "Nothing matched feature '#{display_name(@feature)}'. Available models: #{available_model_names.join(', ')}. " \
              "Available controllers: #{controllers.keys.sort.join(', ')}"
          end
        end

        def model_not_found_message(name)
          "Model '#{display_name(name)}' not found. Available: #{available_model_names.join(', ')}"
        end

        def display_name(name)
          raw = name.to_s.strip
          return '(invalid name)' if raw.include?('..') || raw.start_with?('/', '\\') || raw.include?('\\')

          raw
        end

        def available_model_names
          models.keys.reject { |key| excluded_model?(key) }.map(&:to_s).sort
        end
      end
    end
  end
end
