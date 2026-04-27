# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Formats individual model lines with complexity metadata for AI context documents.
        # Extracts and formats associations, validations, enums, columns, and migration status.
        #
        # This collaborator handles the complex formatting logic for model entries,
        # providing consistent output across different AI assistant providers.
        # It delegates migration recency checking to ContextSummary for DRY compliance.
        #
        # @example Basic usage
        #   formatter = ModelLineFormatter.new(context)
        #   line = formatter.format_line('User', model_data)
        #   # => "- **User** (2a, 1v) [enums: status] — has_many :posts"
        #
        # @example With migrations context
        #   formatter = ModelLineFormatter.new(context_with_migrations)
        #   line = formatter.format_line('Post', post_data)
        #   # => "- **Post** (3a, 2v) [recently migrated]"
        class ModelLineFormatter
          # @param context [Hash] Introspection context hash containing schema and migrations
          # @raise [ArgumentError] if context is not a Hash
          def initialize(context)
            raise ArgumentError, "Context must be a Hash, got #{context.class}" unless context.is_a?(Hash)

            @context = context
          end

          # Formats a single model line with complexity metadata for AI context documents.
          #
          # This is the main public interface that validates input and orchestrates
          # the complete formatting process. It extracts schema and migration data
          # from the context and delegates to the core formatting method.
          #
          # The formatted line includes:
          # - Model name in bold
          # - Association and validation counts (if present)
          # - Enum names (if present)
          # - Top 3 columns with types (if present)
          # - Recently migrated flag (if applicable)
          # - Top 3 associations (if present)
          #
          # @example Basic usage
          #   formatter = ModelLineFormatter.new(context)
          #   line = formatter.format_line('User', user_data)
          #   # => "- **User** (2a, 1v) [enums: status] — has_many :posts"
          #
          # @example With validation errors
          #   formatter.format_line(nil, {}) # => raises ArgumentError
          #   formatter.format_line('User', 'invalid') # => raises ArgumentError
          #
          # @param name [String] Model name (e.g., "User", "BlogPost")
          #   Must not be nil. Used as the primary identifier in the formatted output.
          # @param data [Hash] Model introspection data containing:
          #   - :associations [Array<Hash>] List of association definitions
          #   - :validations [Array<Hash>] List of validation definitions
          #   - :enums [Hash] Enum definitions with keys as enum names
          #   - :table_name [String] Database table name for the model
          #   Must be a Hash, otherwise raises ArgumentError.
          #
          # @return [String] Formatted model line ready for markdown output
          #   Includes model name, counts, enums, columns, migration status, and associations.
          #
          # @raise [ArgumentError] if name is nil
          # @raise [ArgumentError] if data is not a Hash
          #
          # @see #format_model_line Core formatting implementation
          # @see ContextSummary.top_columns For column extraction
          # @see ContextSummary.recently_migrated? For migration checking
          def format_line(name, data)
            raise ArgumentError, 'Model name cannot be nil' unless name
            raise ArgumentError, "Model data must be a Hash, got #{data.class}" unless data.is_a?(Hash)

            schema_tables = @context.dig(:schema, :tables) || {}
            migrations = @context[:migrations]

            format_model_line(name, data, schema_tables, migrations)
          end

          private

          # Core formatting implementation that builds the complete model line
          # @param name [String] Model name
          # @param data [Hash] Model data
          # @param schema_tables [Hash] Schema tables data
          # @param migrations [Hash] Migrations data
          # @return [String] Complete formatted model line
          def format_model_line(name, data, schema_tables, migrations)
            context = FormattingContext.new(data, schema_tables, migrations)

            sections = [
              base_line(name),
              association_count_section(context),
              enums_section(context),
              columns_section(context),
              migration_section(context),
              associations_section(context)
            ]
            sections.join
          end

          # Builds the base model line with bold name
          # @param name [String] Model name
          # @return [String] Base line with model name
          def base_line(name)
            "- **#{name}**"
          end

          # Builds association and validation count section
          # @param context [FormattingContext] Context object with data
          # @return [String] Count section or empty string
          def association_count_section(context)
            self.class.association_count_section(context.data)
          end

          # Builds enum names section
          # @param context [FormattingContext] Context object with data
          # @return [String] Enum section or empty string
          def enums_section(context)
            enum_data = context.data[:enums] || {}
            enum_names = self.class.extract_enum_names(enum_data)
            return '' unless enum_names.any?

            " [enums: #{enum_names.join(', ')}]"
          end

          # Builds columns section with top columns and types
          # @param context [FormattingContext] Context object with data
          # @return [String] Columns section or empty string
          def columns_section(context)
            self.class.columns_section(context.data, context.schema_tables)
          end

          # Builds migration section with recently migrated flag
          # @param context [FormattingContext] Context object with data
          # @return [String] Migration section or empty string
          def migration_section(context)
            self.class.migration_section(context.data, context.migrations)
          end

          # Builds associations section with top 3 associations
          # @param context [FormattingContext] Context object with data
          # @return [String] Associations section or empty string
          def associations_section(context)
            associations = context.data[:associations] || []
            top_assocs = extract_associations(associations)
            return '' if top_assocs.blank?

            " — #{top_assocs}"
          end

          # Simple context object to group related parameters and reduce DataClump
          class FormattingContext
            attr_reader :data, :schema_tables, :migrations

            def initialize(data, schema_tables, migrations)
              @data = data
              @schema_tables = schema_tables
              @migrations = migrations
            end
          end

          # Extracts and formats top 3 associations
          # @param associations [Array<Hash>] Association definitions
          # @return [String] Formatted associations string
          def extract_associations(associations)
            associations.first(3).map { |assoc| self.class.format_association(assoc) }
                                 .reject(&:empty?)
                        .join(', ')
          end

          class << self
            # Builds association and validation count section (class method)
            # @param data [Hash] Model data
            # @return [String] Count section or empty string
            def association_count_section(data)
              associations = data[:associations] || []
              validations = data[:validations] || []
              assoc_count = associations.size
              val_count = validations.size
              return '' unless assoc_count.positive? || val_count.positive?

              " (#{assoc_count}a, #{val_count}v)"
            end

            # Extracts enum names from enum data (class method)
            # @param enum_data [Hash] Enum definitions
            # @return [Array<String>] List of enum names
            def extract_enum_names(enum_data)
              return [] unless enum_data.is_a?(Hash)
              return [] if enum_data.empty?

              enum_values = enum_data.values.compact
              return [] if enum_values.empty?

              enum_data.keys.compact
            end

            # Builds columns section with top columns and types (class method)
            # @param data [Hash] Model data
            # @param schema_tables [Hash] Schema tables data
            # @return [String] Columns section or empty string
            def columns_section(data, schema_tables)
              table_name = data[:table_name]
              return '' unless table_name

              cols = ContextSummary.top_columns(schema_tables[table_name])
              return '' unless cols.any?

              " [cols: #{cols.map { |column| "#{column[:name]}:#{column[:type]}" }.join(', ')}]"
            end

            # Builds migration section with recently migrated flag (class method)
            # @param data [Hash] Model data
            # @param migrations [Hash] Migrations data
            # @return [String] Migration section or empty string
            def migration_section(data, migrations)
              table_name = data[:table_name]
              return '' unless table_name && ContextSummary.recently_migrated?(table_name, migrations)

              ' [recently migrated]'
            end

            # Formats a single association using Ruby 3.2 pattern matching (class method)
            # @param association [Hash] Association definition
            # @return [String] Formatted association string
            def format_association(association)
              return '' unless association.is_a?(Hash)

              type = association[:type]
              name = association[:name]

              case { type: type, name: name }
              in { type: nil, name: nil }
                ''
              in { type: nil, name: }
                " :#{name}"
              in { type:, name: nil }
                "#{type} :"
              in { type:, name: }
                "#{type} :#{name}"
              end
            end
          end
        end
      end
    end
  end
end
