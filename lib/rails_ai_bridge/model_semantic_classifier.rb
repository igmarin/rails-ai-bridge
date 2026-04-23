# frozen_string_literal: true

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
    ##
    # Initialize the classifier with configured core and through-join model names.
    # @param [Array<String>, Set<String>] core_model_names - Model class names treated as core entities; entries are converted to strings and stored as a Set.
    ##
    # Initialize the classifier with configured core and through model names.
    # @param [Array<String>] core_model_names - Names of models considered core; entries are converted to strings and stored as a Set.
    # @param [Set<String>, Array<String>] through_model_names - Model class names identified as through/join models (typically from `.through_join_model_names`); entries are converted to strings and stored as a Set.
    def initialize(core_model_names: [], through_model_names: Set.new)
      @core = core_model_names.to_set(&:to_s)
      @through = through_model_names.to_set(&:to_s)
    end

    # @param model [Class] ActiveRecord model
    ##
    # Classifies an ActiveRecord model into a semantic tier for downstream semantic context.
    # @param [Class] model - The ActiveRecord model class to classify.
    # @return [Hash{Symbol => String}] A hash with keys:
    #   - :tier => one of "core_entity", "pure_join", "rich_join", or "supporting".
    ##
    # Classifies an ActiveRecord model into a semantic tier and provides a machine-oriented reason code.
    # @param [Class] model - The ActiveRecord model class to classify.
    # @return [Hash] A hash with keys :tier and :reason. :tier is a string such as "core_entity", "pure_join", "rich_join", or "supporting". :reason is a machine-oriented code explaining the classification. On unexpected errors the method returns a :tier of "supporting" and a :reason beginning with "classification_error: ".
    def call(model)
      return tier(:supporting, 'unnamed_model') if model.name.blank?
      return tier(:core_entity, 'configured_core_model') if @core.include?(model.name)

      column_names = safe_column_names(model)
      return tier(:supporting, 'no_columns_loaded') if column_names.empty?

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

    ##
    # Classifies a model as a pure join or a supporting model when the model has no payload columns.
    # @param [Boolean] is_through - True if the model is recognized as a through/join model.
    # @param [Integer] belongs_count - The count of `belongs_to` associations on the model.
    # @return [Hash] A hash with keys `:tier` (the tier name as a string) and `:reason` (a machine-oriented reason string).
    def classify_without_payload(is_through, belongs_count)
      if is_through && belongs_count >= 2
        tier(:pure_join, 'through_join_without_payload_columns')
      else
        tier(:supporting, 'not_classified_as_join_table')
      end
    end

    ##
    # Determine the tier for a model that has additional (payload) columns.
    # @param [Boolean] is_through - Whether the model is recognized as a `has_many :through` join model.
    # @param [Integer] belongs_count - Number of `belongs_to` associations declared on the model.
    ##
    # Classifies a model that has payload columns as either a rich join or a supporting model.
    # @param [Boolean] is_through - Whether the model is recognized as a `through` join model.
    # @param [Integer] belongs_count - Number of `belongs_to` associations on the model.
    # @return [Hash] A hash with keys `:tier` (String) and `:reason` (String) describing the classification.
    def classify_with_payload(is_through, belongs_count)
      if is_through && belongs_count >= 2
        tier(:rich_join, 'through_join_with_payload_columns')
      else
        tier(:supporting, 'domain_or_misc_model')
      end
    end

    ##
    # Build a formatted classification hash with stringified tier name and reason.
    # @param [Symbol,String] name - The tier identifier (e.g., :core_entity, :pure_join).
    # @param [String] reason - Machine-oriented reason code explaining the classification.
    ##
    # Build a tier result hash for classification.
    # @param [#to_s] name - The tier identifier; will be converted to a string.
    # @param [String] reason - Explanation for why the tier was assigned.
    # @return [Hash] A hash with keys `:tier` (string) and `:reason` (string).
    def tier(name, reason)
      { tier: name.to_s, reason: reason }
    end

    ##
    # Retrieve column names for the given model as strings.
    # @param [Class] model - An ActiveRecord model class or instance that responds to `column_names`.
    ##
    # Return the model's column names as strings, or an empty array if they cannot be read.
    # @param [Class] model - An ActiveRecord model class (or any object responding to `column_names`).
    # @return [Array<String>] Column names converted to strings; returns an empty array if reading `column_names` raises an error.
    def safe_column_names(model)
      model.column_names.map(&:to_s)
    rescue StandardError
      []
    end

    ##
    # Determine which metadata column names are present for a given model.
    # Checks the BASE_METADATA list, the model's inheritance column, and "lock_version" against the provided column names.
    # @param [Class] model - The ActiveRecord model class whose inheritance column may be included.
    # @param [Array<String>] column_names - The list of column names available on the model.
    ##
    # Collects the metadata column names present in the given column list.
    # Includes BASE_METADATA entries found in `column_names`, the model's
    # `inheritance_column` if present, and `"lock_version"` if present.
    # @param [Class, Object] model - The ActiveRecord model (class or instance) whose `inheritance_column` will be considered.
    # @param [Array<String>] column_names - The list of column names to check.
    # @return [Array<String>] Unique metadata column names from `column_names` (base metadata, the model's inheritance column if present, and `"lock_version"` if present).
    def metadata_column_names(model, column_names)
      meta = BASE_METADATA.select { |c| column_names.include?(c) }
      inc = model.inheritance_column.to_s
      meta << inc if column_names.include?(inc)
      meta << 'lock_version' if column_names.include?('lock_version')
      meta.uniq
    end
  end
end
