# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Template-method base for section formatters that follow the standard
      # guard pattern: extract data by key, return nil when absent or errored,
      # then delegate to {#render}.
      #
      # Subclasses declare their context key with +section+ and implement
      # +render(data)+:
      #
      #   class SchemaFormatter < Formatters::Sections::SectionFormatter
      #     section :schema
      #
      #     private
      #
      #     def render(data)
      #       # build and return markdown string, or nil
      #     end
      #   end
      #
      # @see Base
      class SectionFormatter < Base
        class << self
          # @return [Symbol] the context key this formatter reads from
          attr_reader :section_key

          private

          # Declares the context key this formatter reads from (+context[key]+).
          # @param key [Symbol] introspection section key (e.g. +:schema+, +:routes+)
          # @return [void]
          def section(key)
            @section_key = key
          end
        end

        # Extracts data from +context[section_key]+, applies standard guards,
        # and delegates to {#render}.
        #
        # @return [String, nil]
        def call
          data = context[self.class.section_key]
          return unless data
          return if data[:error]

          render(data)
        end

        private

        # Subclasses implement this to produce markdown output.
        #
        # @param _data [Hash, Object] the section data from context
        # @return [String, nil]
        def render(_data)
          raise NotImplementedError, "#{self.class}#render is not implemented"
        end
      end
    end
  end
end
