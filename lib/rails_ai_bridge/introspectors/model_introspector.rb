# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts ActiveRecord model metadata: associations, validations,
    # scopes, enums, callbacks, and class-level configuration.
    class ModelIntrospector
      attr_reader :app, :config

      EXCLUDED_CALLBACKS = %w[autosave_associated_records_for].freeze

      def initialize(app)
        @app    = app
        @config = RailsAiBridge.configuration
      end

      # @return [Hash] model metadata keyed by model name
      def call
        eager_load_models!
        models = discover_models

        models.each_with_object({}) do |model, hash|
          hash[model.name] = extract_model_details(model)
        rescue => e
          hash[model.name] = { error: e.message }
        end
      end

      private

      def eager_load_models!
        Rails.application.eager_load! unless Rails.application.config.eager_load
      rescue
        # In some environments (CI, Claude Code) eager_load may partially fail
        nil
      end

      def model_table_excluded?(model)
        # model.table_name can raise on STI subclasses that inherit a non-existent table
        tn = model.table_name
        return false if tn.nil? || tn.to_s.empty?

        config.excluded_table?(tn)
      rescue StandardError
        false
      end

      def discover_models
        return [] unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.descendants.reject do |model|
          model.abstract_class? ||
            model.name.nil? ||
            config.excluded_models.include?(model.name) ||
            model_table_excluded?(model)
        end.sort_by(&:name)
      end

      def extract_model_details(model)
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

        # Source-based macro extractions
        macros = extract_source_macros(model)
        details.merge!(macros)

        details.compact
      end

      def extract_associations(model)
        model.reflect_on_all_associations.map do |assoc|
          detail = {
            name: assoc.name.to_s,
            type: assoc.macro.to_s, # :has_many, :belongs_to, :has_one, :has_and_belongs_to_many
            class_name: assoc.class_name,
            foreign_key: assoc.foreign_key.to_s
          }
          detail[:through]    = assoc.options[:through].to_s if assoc.options[:through]
          detail[:polymorphic] = true if assoc.options[:polymorphic]
          detail[:dependent]  = assoc.options[:dependent].to_s if assoc.options[:dependent]
          detail[:optional]   = assoc.options[:optional] if assoc.options.key?(:optional)
          detail.compact
        end
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
      rescue
        []
      end

      def model_source_path(model)
        root = app.root.to_s
        underscored = model.name.underscore
        File.join(root, "app", "models", "#{underscored}.rb")
      end

      def extract_enums(model)
        return {} unless model.respond_to?(:defined_enums)

        model.defined_enums.transform_values do |mapping|
          mapping.keys
        end
      end

      def extract_callbacks(model)
        callback_types = %i[
          before_validation after_validation
          before_save after_save
          before_create after_create
          before_update after_update
          before_destroy after_destroy
          after_commit after_rollback
        ]

        callback_types.each_with_object({}) do |type, hash|
          callbacks = model.send(:"_#{type}_callbacks").reject do |cb|
            cb.filter.to_s.start_with?(*EXCLUDED_CALLBACKS) || cb.filter.is_a?(Proc)
          end

          next if callbacks.empty?

          hash[type.to_s] = callbacks.map { |cb| cb.filter.to_s }
        end
      rescue
        {}
      end

      def extract_concerns(model)
        model.ancestors
          .select { |mod| mod.is_a?(Module) && !mod.is_a?(Class) }
          .reject { |mod| mod.name&.start_with?("ActiveRecord", "ActiveModel", "ActiveSupport") }
          .map(&:name)
          .compact
      end

      def extract_public_class_methods(model)
        (model.methods - ActiveRecord::Base.methods - Object.methods)
          .reject { |m| m.to_s.start_with?("_", "autosave") }
          .sort
          .first(30) # Cap to avoid noise
          .map(&:to_s)
      end

      def extract_public_instance_methods(model)
        (model.instance_methods - ActiveRecord::Base.instance_methods - Object.instance_methods)
          .reject { |m| m.to_s.start_with?("_", "autosave", "validate_associated") }
          .sort
          .first(30)
          .map(&:to_s)
      end

      def extract_source_macros(model)
        path = model_source_path(model)
        return {} unless path && File.exist?(path)

        source = File.read(path)
        macros = {}

        macros[:has_secure_password] = true if source.match?(/\bhas_secure_password\b/)
        macros[:encrypts] = source.scan(/\bencrypts\s+(.+)/).flat_map { |m| m[0].scan(/:(\w+)/).flatten } if source.match?(/\bencrypts\s+:/)
        macros[:normalizes] = source.scan(/\bnormalizes\s+(.+)/).flat_map { |m| m[0].scan(/:(\w+)/).flatten } if source.match?(/\bnormalizes\s+:/)
        macros[:has_one_attached] = source.scan(/\bhas_one_attached\s+:(\w+)/).flatten if source.match?(/\bhas_one_attached\s+:/)
        macros[:has_many_attached] = source.scan(/\bhas_many_attached\s+:(\w+)/).flatten if source.match?(/\bhas_many_attached\s+:/)
        macros[:has_rich_text] = source.scan(/\bhas_rich_text\s+:(\w+)/).flatten if source.match?(/\bhas_rich_text\s+:/)
        macros[:broadcasts] = source.scan(/\b(broadcasts_to|broadcasts_refreshes_to|broadcasts)\b/).flatten.uniq if source.match?(/\bbroadcasts/)
        macros[:generates_token_for] = source.scan(/\bgenerates_token_for\s+:(\w+)/).flatten if source.match?(/\bgenerates_token_for\s+:/)
        macros[:serialize] = source.scan(/\bserialize\s+:(\w+)/).flatten if source.match?(/\bserialize\s+:/)
        macros[:store] = source.scan(/\bstore(?:_accessor)?\s+:(\w+)/).flatten if source.match?(/\bstore(?:_accessor)?\s+:/)

        # Delegations
        delegations = source.scan(/\bdelegate\s+(.+?),\s*to:\s*:(\w+)/).map do |methods_str, target|
          { methods: methods_str.scan(/:(\w+)/).flatten, to: target }
        end
        macros[:delegations] = delegations if delegations.any?

        if (dmt = source.match(/\bdelegate_missing_to\s+:(\w+)/))
          macros[:delegate_missing_to] = dmt[1]
        end

        # Remove empty arrays
        macros.reject { |_, v| v.is_a?(Array) && v.empty? }
      rescue
        {}
      end

      def sanitize_options(options)
        # Remove procs and complex objects that don't serialize well
        options.reject { |_k, v| v.is_a?(Proc) || v.is_a?(Regexp) }
               .transform_values(&:to_s)
      end
    end
  end
end
