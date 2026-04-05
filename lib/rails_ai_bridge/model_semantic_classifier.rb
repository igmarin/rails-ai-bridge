# frozen_string_literal: true

require "set"

module RailsAiBridge
  # Heuristic classification of ActiveRecord models for semantic context:
  # * +core_entity+ — listed in {Config::Introspection#core_models}
  # * +pure_join+ — +has_many :through+ join model whose columns are only metadata and +belongs_to+ foreign keys
  # * +rich_join+ — same as pure join pattern but with extra payload columns
  # * +supporting+ — everything else (typical domain models, STI, polymorphic owners, etc.)
  #
  # STI +inheritance_column+, +lock_version+, and standard timestamp columns are treated as metadata.
  # Counter caches and other extra columns disqualify a model from +pure_join+.
  class ModelSemanticClassifier
    BASE_METADATA = %w[id created_at updated_at created_on updated_on].freeze

    # Collects model class names used as the join model in a +through:+ association.
    #
    # @return [Set<String>]
    def self.through_join_model_names
      return Set.new unless defined?(ActiveRecord::Base)

      names = Set.new
      ActiveRecord::Base.descendants.each do |model|
        next if model.abstract_class? || model.name.blank?

        model.reflect_on_all_associations.each do |assoc|
          through = assoc.options[:through]
          next unless through

          join_assoc = model.reflect_on_association(through)
          join_klass = join_assoc&.klass
          names << join_klass.name if join_klass&.name.present?
        end
      rescue StandardError
        next
      end
      names
    end

    # @param core_model_names [Array<String, Symbol>] from {Configuration#core_models}
    # @param through_model_names [Set<String>, Array<String>] from {.through_join_model_names}
    def initialize(core_model_names: [], through_model_names: Set.new)
      @core = core_model_names.map(&:to_s).to_set
      @through = through_model_names.map(&:to_s).to_set
    end

    # @param model [Class] ActiveRecord model
    # @return [Hash{Symbol => String}] +:tier+ and +:reason+ (machine-oriented; for MCP transparency)
    def call(model)
      return tier(:supporting, "unnamed_model") if model.name.blank?
      return tier(:core_entity, "configured_core_model") if @core.include?(model.name)

      column_names = safe_column_names(model)
      return tier(:supporting, "no_columns_loaded") if column_names.empty?

      belongs = model.reflect_on_all_associations.select { |a| a.macro == :belongs_to }
      fk_columns = belongs.filter_map { |a| a.foreign_key&.to_s }.uniq
      allowed = (metadata_column_names(model, column_names) + fk_columns).uniq
      extra = column_names - allowed
      is_through = @through.include?(model.name)
      belongs_count = belongs.size

      if extra.empty?
        classify_without_payload(is_through, belongs_count)
      else
        classify_with_payload(is_through, belongs_count)
      end
    rescue StandardError => e
      tier(:supporting, "classification_error: #{e.message}")
    end

    private

    def classify_without_payload(is_through, belongs_count)
      if is_through && belongs_count >= 2
        tier(:pure_join, "through_join_without_payload_columns")
      else
        tier(:supporting, "not_classified_as_join_table")
      end
    end

    def classify_with_payload(is_through, belongs_count)
      if is_through && belongs_count >= 2
        tier(:rich_join, "through_join_with_payload_columns")
      else
        tier(:supporting, "domain_or_misc_model")
      end
    end

    def tier(name, reason)
      { tier: name.to_s, reason: reason }
    end

    def safe_column_names(model)
      model.column_names.map(&:to_s)
    rescue StandardError
      []
    end

    def metadata_column_names(model, column_names)
      meta = BASE_METADATA.select { |c| column_names.include?(c) }
      inc = model.inheritance_column.to_s
      meta << inc if column_names.include?(inc)
      meta << "lock_version" if column_names.include?("lock_version")
      meta.uniq
    end
  end
end
