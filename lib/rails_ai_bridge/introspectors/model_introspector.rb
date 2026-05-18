# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts ActiveRecord model metadata: associations, validations,
    # scopes, enums, callbacks, and class-level configuration.
    class ModelIntrospector
      include ModelSemanticEnrichment

      attr_reader :app, :config

      # Callback name prefixes omitted from generated model context to reduce framework noise.
      EXCLUDED_CALLBACKS = %w[autosave_associated_records_for].freeze

      # Initializes the ModelIntrospector with the host Rails application and loads the library configuration.
      #
      # Also prepares a path resolver so source-based metadata honors custom Rails path configuration.
      #
      # @param [Object] app - The Rails application instance to introspect.
      def initialize(app)
        @app    = app
        @config = RailsAiBridge.configuration
        @path_resolver = PathResolver.new(app)
      end

      # Builds a metadata map for all discovered ActiveRecord models.
      #
      # For each model, the map contains the extracted metadata hash; if extraction fails for a model,
      # its value will be a hash with an `:error` key and the error message.
      #
      # @return [Hash<String, Hash>] Mapping from model name to its metadata hash or
      #   `{ error: String }` on failure.
      def call
        eager_load_models!
        models = discover_models
        through_names = ModelSemanticClassifier.through_join_model_names
        classifier = ModelSemanticClassifier.new(
          core_model_names: config.core_models,
          through_model_names: through_names
        )

        models.each_with_object({}) do |model, hash|
          hash[model.name] = extract_model_details(model, classifier)
        rescue StandardError => error
          hash[model.name] = { error: error.message }
        end
      end

      private

      def eager_load_models!
        Rails.application.eager_load! unless Rails.application.config.eager_load
      rescue StandardError
        # In some environments (CI, Claude Code) eager_load may partially fail
        nil
      end

      ##
      # Determines whether the model's database table is excluded by the inspector configuration.
      # @param [Class] model - The ActiveRecord model class whose table name will be checked.
      # @return [Boolean] `true` if the model's table name is listed as excluded in the configuration,
      #   `false` otherwise (returns `false` if the model has no table name or if an error occurs
      #   while retrieving it).
      def model_table_excluded?(model)
        # model.table_name can raise on STI subclasses that inherit a non-existent table
        tn = model.table_name
        return false if tn.nil? || tn.to_s.empty?

        config.excluded_table?(tn)
      rescue StandardError
        false
      end

      # Discovers application ActiveRecord model classes subject to configuration and table exclusions.
      #
      # Returns an array of model classes sorted by name. The list excludes:
      # - models if `ActiveRecord::Base` is not defined (returns an empty array),
      # - abstract models,
      # - models without a name,
      # - models whose name appears in `config.excluded_models`,
      # - models whose table is excluded via `model_table_excluded?`.
      #
      # Returns an empty array if `ActiveRecord::Base` is not defined.
      #
      # @return [Array<Class>] Array of discovered model classes sorted by name.
      def discover_models
        return [] unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.descendants.reject do |model|
          model.abstract_class? ||
            model.name.nil? ||
            config.excluded_models.include?(model.name) ||
            model_table_excluded?(model)
        end.sort_by(&:name)
      end

      # Build a metadata hash describing the given ActiveRecord model.
      #
      # Populates model structural metadata, semantic classification results, and source-derived
      # macro signals.
      #
      # @param [Class] model - The ActiveRecord model class to introspect.
      # @param [Object] classifier - A semantic classifier responding to `call(model)` that returns
      #   a hash with `:tier` and `:reason`.
      # @return [Hash] A compacted hash of metadata including:
      #   - `:table_name` - model's table name
      #   - `:associations` - array of association descriptors
      #   - `:validations` - array of validation descriptors
      #   - `:scopes` - array of scope names
      #   - `:enums` - hash of enum attributes to keys
      #   - `:callbacks` - hash of callbacks by type
      #   - `:concerns` - array of included concern module names
      #   - `:class_methods` - array of public class method names (capped)
      #   - `:instance_methods` - array of public instance method names (capped)
      #   - `:semantic_tier` - classifier-assigned tier
      #   - `:semantic_tier_reason` - classifier-provided reason
      #   - additional keys extracted from the model source (e.g., `:has_secure_password`, `:encrypts`, attachment macros, `:delegations`, etc.)
      #   Nil-valued entries are removed from the returned hash.
      def extract_model_details(model, classifier)
        details = {
          table_name: model.table_name,
          associations: extract_associations(model),
          validations: extract_validations(model),
          scopes: extract_scopes(model),
          enums: extract_enums(model),
          callbacks: extract_callbacks(model),
          concerns: extract_concerns(model),
          class_methods: extract_public_class_methods(model),
          instance_methods: extract_public_instance_methods(model)
        }

        tier = classifier.call(model)
        details[:semantic_tier] = tier[:tier]
        details[:semantic_tier_reason] = tier[:reason]

        # Source-based macro extractions
        macros = extract_source_macros(model)
        details.merge!(macros)

        # Rubydex semantic analysis (when available)
        semantic = extract_semantic_data(model)
        details.merge!(semantic) if semantic.any?

        details.compact
      end

      def extract_associations(model)
        model.reflect_on_all_associations.map do |assoc|
          build_association_detail(assoc)
        end
      end

      def build_association_detail(assoc)
        opts = assoc.options
        detail = {
          name: assoc.name.to_s,
          type: assoc.macro.to_s,
          class_name: assoc.class_name,
          foreign_key: assoc.foreign_key.to_s
        }
        detail[:through] = opts[:through].to_s if opts[:through]
        detail[:polymorphic] = true if opts[:polymorphic]
        detail[:dependent]  = opts[:dependent].to_s if opts[:dependent]
        detail[:optional]   = opts[:optional] if opts.key?(:optional)
        detail.compact
      end

      def extract_validations(model)
        model.validators.map do |validator|
          {
            kind: validator.kind.to_s,
            attributes: validator.attributes.map(&:to_s),
            options: sanitize_options(validator.options)
          }
        end
      end

      def extract_scopes(model)
        source_path = model_source_path(model)
        return [] unless source_path && File.exist?(source_path)

        File.read(source_path).scan(/^\s*scope\s+:(\w+)/).flatten
      rescue StandardError
        []
      end

      # Resolves the source file for an ActiveRecord model using the configured
      # logical +app/models+ path before falling back to conventional locations.
      #
      # @param model [Class] ActiveRecord model class
      # @return [String, nil] absolute source path when present
      def model_source_path(model)
        underscored = model.name.underscore
        @path_resolver.existing_file_for('app/models', "#{underscored}.rb")
      end

      def extract_enums(model)
        return {} unless model.respond_to?(:defined_enums)

        model.defined_enums.transform_values(&:keys)
      end

      def extract_callbacks(model)
        CallbackExtractor.new(model, excluded_prefixes: EXCLUDED_CALLBACKS).call
      end

      def extract_concerns(model)
        model.ancestors
             .select { |mod| mod.is_a?(Module) && !mod.is_a?(Class) }
             .reject { |mod| mod.name&.start_with?('ActiveRecord', 'ActiveModel', 'ActiveSupport') }
             .map(&:name)
             .compact
      end

      def extract_public_class_methods(model)
        (model.methods - ActiveRecord::Base.methods - Object.methods)
          .reject { |method_name| method_name.to_s.start_with?('_', 'autosave') }
          .sort
          .first(30)
          .map(&:to_s)
      end

      def extract_public_instance_methods(model)
        (model.instance_methods - ActiveRecord::Base.instance_methods - Object.instance_methods)
          .reject { |method_name| method_name.to_s.start_with?('_', 'autosave', 'validate_associated') }
          .sort
          .first(30)
          .map(&:to_s)
      end

      def extract_source_macros(model)
        path = model_source_path(model)
        return {} unless path && File.exist?(path)

        SourceMacroExtractor.new(File.read(path)).call
      rescue StandardError
        {}
      end

      def sanitize_options(options)
        options.reject { |_key, val| val.is_a?(Proc) || val.is_a?(Regexp) }
               .transform_values(&:to_s)
      end
    end
  end
end
