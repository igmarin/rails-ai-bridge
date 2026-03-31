# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Renders complete detail for a single ActiveRecord model.
      class SingleModelFormatter
        # @param name [String] model class name
        # @param data [Hash] model data from {Introspectors::ModelIntrospector}
        def initialize(name:, data:)
          @name = name
          @data = data
        end

        # @return [String] full Markdown representation of the model
        def call
          lines = [ "# #{@name}", "" ]
          lines << "**Table:** `#{@data[:table_name]}`" if @data[:table_name]

          if @data[:associations]&.any?
            lines << "" << "## Associations"
            @data[:associations].each do |a|
              line = "- `#{a[:type]}` **#{a[:name]}**"
              line += " (class: #{a[:class_name]})" if a[:class_name] && a[:class_name] != a[:name].to_s.classify
              line += " through: #{a[:through]}" if a[:through]
              line += " [polymorphic]" if a[:polymorphic]
              line += " dependent: #{a[:dependent]}" if a[:dependent]
              lines << line
            end
          end

          if @data[:validations]&.any?
            lines << "" << "## Validations"
            @data[:validations].each do |v|
              attrs = v[:attributes].join(", ")
              opts  = v[:options]&.any? ? " (#{v[:options].map { |k, val| "#{k}: #{val}" }.join(', ')})" : ""
              lines << "- `#{v[:kind]}` on #{attrs}#{opts}"
            end
          end

          if @data[:enums]&.any?
            lines << "" << "## Enums"
            @data[:enums].each do |attr, values|
              lines << "- `#{attr}`: #{values.join(', ')}"
            end
          end

          if @data[:scopes]&.any?
            lines << "" << "## Scopes"
            lines << @data[:scopes].map { |s| "- `#{s}`" }.join("\n")
          end

          if @data[:callbacks]&.any?
            lines << "" << "## Callbacks"
            @data[:callbacks].each do |type, methods|
              lines << "- `#{type}`: #{methods.join(', ')}"
            end
          end

          if @data[:concerns]&.any?
            lines << "" << "## Concerns"
            lines << @data[:concerns].map { |c| "- #{c}" }.join("\n")
          end

          if @data[:instance_methods]&.any?
            lines << "" << "## Key instance methods"
            lines << @data[:instance_methods].first(15).map { |m| "- `#{m}`" }.join("\n")
          end

          lines.join("\n")
        end
      end
    end
  end
end
