# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ModelIntrospector
      # Extracts association metadata from an ActiveRecord model.
      #
      # Analyzes ActiveRecord reflections to build a structural representation
      # of the model's associations, including types, classes, foreign keys,
      # and relevant options like polymorphism.
      class AssociationExtractor
        # Builds hash details for a single ActiveRecord association.
        class DetailBuilder
          def initialize(assoc)
            @assoc = assoc
            @opts = assoc.options
          end

          def build
            base_detail.merge(association_options).compact
          end

          private

          attr_reader :assoc, :opts

          def base_detail
            {
              name: assoc.name.to_s,
              type: assoc.macro.to_s,
              class_name: assoc.class_name,
              foreign_key: assoc.foreign_key.to_s
            }
          end

          def association_options
            {
              through: opts[:through]&.to_s,
              dependent: opts[:dependent]&.to_s,
              polymorphic: (true if opts[:polymorphic]),
              optional: (opts[:optional] if opts.key?(:optional))
            }.compact
          end
        end

        # @param model [Class] ActiveRecord model class
        def initialize(model)
          @model = model
        end

        # @return [Array<Hash>] array of association descriptors
        def call
          model.reflect_on_all_associations.map do |assoc|
            DetailBuilder.new(assoc).build
          end
        rescue StandardError
          []
        end

        private

        attr_reader :model
      end
    end
  end
end
