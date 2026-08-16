# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders complete detail for a single ActiveRecord model.
      class SingleModelFormatter
        # Source-regex macros. Rendered as +[INFERRED]+ — never +[VERIFIED]+.
        SOURCE_MACRO_KEYS = %i[
          has_secure_password encrypts normalizes has_one_attached
          has_many_attached has_rich_text broadcasts generates_token_for
          serialize store delegations delegate_missing_to
        ].freeze

        # @param name [String] model class name
        # @param data [Hash] model payload from {Introspectors::ModelIntrospector}
        ##
        # Create a formatter for a single model using the provided introspection data.
        # @param [String] name - The model's class name.
        # @param [Hash] data - Introspection hash containing model details (table, associations, validations,
        # enums, scopes, callbacks, concerns, instance_methods, etc.).
        # The values are stored on the instance without validation.
        def initialize(name:, data:)
          @name = name
          @data = data
        end

        ##
        # Format model introspection data into a Markdown document.
        #
        # The output includes the model name header and, when present in the input data,
        # sections for table name, semantic tier (and tier reason), associations,
        # validations, enums, scopes, callbacks, concerns, and up to the first 15 key
        # instance methods.
        ##
        # Builds a Markdown document describing the given ActiveRecord model's introspected details.
        # The output may include table name, semantic tier and reason, associations, validations, enums,
        #  scopes, callbacks, concerns, source macros, and up to 15 key instance methods depending on the data provided.
        # Associations from ActiveRecord reflection are tagged +[VERIFIED]+; regex-extracted
        # scopes and source macros are tagged +[INFERRED]+.
        # @return [String] The Markdown-formatted representation of the model.
        def call
          lines = ["# #{@name}", '']
          lines << "**Table:** `#{@data[:table_name]}`" if @data[:table_name]
          if @data[:semantic_tier].present?
            lines << "**Semantic tier:** `#{@data[:semantic_tier]}`"
            lines << "**Tier reason:** #{@data[:semantic_tier_reason]}" if @data[:semantic_tier_reason].present?
          end

          if @data[:associations]&.any?
            lines << '' << '## Associations'
            @data[:associations].each do |a|
              line = "- `#{a[:type]}` **#{a[:name]}**"
              line += " (class: #{a[:class_name]})" if a[:class_name] && a[:class_name] != a[:name].to_s.classify
              line += " through: #{a[:through]}" if a[:through]
              line += ' [polymorphic]' if a[:polymorphic]
              line += " dependent: #{a[:dependent]}" if a[:dependent]
              lines << ConfidenceTag.tagged(line, a[:source] || :reflection)
            end
          end

          if @data[:validations]&.any?
            lines << '' << '## Validations'
            @data[:validations].each do |v|
              attrs = v[:attributes].join(', ')
              opts  = v[:options]&.any? ? " (#{v[:options].map { |k, val| "#{k}: #{val}" }.join(', ')})" : ''
              lines << "- `#{v[:kind]}` on #{attrs}#{opts}"
            end
          end

          if @data[:enums]&.any?
            lines << '' << '## Enums'
            @data[:enums].each do |attr, values|
              lines << "- `#{attr}`: #{values.join(', ')}"
            end
          end

          if @data[:scopes]&.any?
            lines << '' << '## Scopes'
            lines << @data[:scopes].map { |s| ConfidenceTag.tagged("- `#{s}`", :regex) }.join("\n")
          end

          if @data[:callbacks]&.any?
            lines << '' << '## Callbacks'
            @data[:callbacks].each do |type, methods|
              lines << "- `#{type}`: #{methods.join(', ')}"
            end
          end

          if @data[:concerns]&.any?
            lines << '' << '## Concerns'
            lines << @data[:concerns].map { |c| "- #{c}" }.join("\n")
          end

          if @data[:instance_methods]&.any?
            lines << '' << '## Key instance methods'
            lines << @data[:instance_methods].first(15).map { |m| "- `#{m}`" }.join("\n")
          end

          append_source_macros(lines)

          lines.join("\n")
        end

        private

        def append_source_macros(lines)
          present = SOURCE_MACRO_KEYS.select { |key| macro_present?(@data[key]) }
          return if present.empty?

          lines << '' << '## Source macros'
          present.each do |key|
            lines << ConfidenceTag.tagged("- #{format_macro(key, @data[key])}", :regex)
          end
        end

        def macro_present?(value)
          value == true || value.present?
        end

        def format_macro(key, value)
          case value
          when true
            "`#{key}`"
          when Array
            "`#{key}`: #{format_macro_list(value)}"
          else
            "`#{key}`: #{value}"
          end
        end

        def format_macro_list(value)
          return value.join(', ') unless value.first.is_a?(Hash)

          value.map { |entry| "#{Array(entry[:methods]).join(', ')} → #{entry[:to]}" }.join('; ')
        end
      end
    end
  end
end
