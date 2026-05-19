# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ModelIntrospector
      # Extracts public class and instance methods from an ActiveRecord model.
      #
      # Filters out standard ActiveRecord and Object methods to highlight
      # custom domain logic implemented on the model.
      class MethodExtractor
        # @param model [Class] ActiveRecord model class
        def initialize(model)
          @model = model
        end

        # @return [Array<String>] array of public class method names
        def extract_class_methods
          (model.methods - ActiveRecord::Base.methods - Object.methods)
            .reject { |method_name| method_name.to_s.start_with?('_', 'autosave') }
            .sort
            .first(30)
            .map(&:to_s)
        rescue StandardError
          []
        end

        # @return [Array<String>] array of public instance method names
        def extract_instance_methods
          (model.instance_methods - ActiveRecord::Base.instance_methods - Object.instance_methods)
            .reject { |method_name| method_name.to_s.start_with?('_', 'autosave', 'validate_associated') }
            .sort
            .first(30)
            .map(&:to_s)
        rescue StandardError
          []
        end

        private

        attr_reader :model
      end
    end
  end
end
