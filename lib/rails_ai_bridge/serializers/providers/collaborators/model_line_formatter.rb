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

            ModelLineRenderer.format(ModelConfiguration.new(name, data, schema_tables, migrations))
          end

          # Configuration object for model line formatting
          class ModelConfiguration
            attr_reader :name, :data, :schema_tables, :migrations

            def initialize(name, data, schema_tables, migrations)
              @name = name
              @data = data
              @schema_tables = schema_tables
              @migrations = migrations
            end
          end

          # Utility class for model line formatting
          class ModelLineRenderer
            def self.format(configuration)
              LineBuilder.new(configuration).build
            end
          end

          # Utility class for extracting enum names
          class EnumExtractor
            def self.extract(enum_data)
              return [] unless enum_data.is_a?(Hash)
              return [] if enum_data.empty?

              enum_values = enum_data.values.compact
              return [] if enum_values.empty?

              enum_data.keys.compact
            end
          end

          # Utility class for extracting associations
          class AssociationExtractor
            def self.extract(associations)
              associations.first(3).map(&method(:format_association))
                          .reject(&:empty?)
                          .join(', ')
            end

            def self.format_association(association)
              return '' unless association.is_a?(Hash)

              type = association[:type]
              name = association[:name]

              AssociationFormatter.call(type, name)
            end
          end

          # Builds formatted model line components
          class LineBuilder
            def initialize(configuration)
              @configuration = configuration
            end

            def build
              sections = [
                base_line,
                association_count_section,
                enums_section,
                columns_section,
                migration_section,
                associations_section
              ]
              sections.join
            end

            private

            attr_reader :configuration

            def name
              configuration.name
            end

            def data
              configuration.data
            end

            def schema_tables
              configuration.schema_tables
            end

            def migrations
              configuration.migrations
            end

            def base_line
              "- **#{name}**"
            end

            def association_count_section
              associations = data[:associations] || []
              validations = data[:validations] || []
              AssociationCountBuilder.build(associations, validations)
            end

            def enums_section
              enum_data = data[:enums] || {}
              EnumSectionBuilder.build(enum_data)
            end

            def columns_section
              table_name = data[:table_name]
              ColumnsSectionBuilder.build(table_name, schema_tables)
            end

            def migration_section
              table_name = data[:table_name]
              return '' unless table_name && MigrationChecker.recently_migrated?(table_name, migrations)

              ' [recently migrated]'
            end

            def associations_section
              associations = data[:associations] || []
              top_assocs = AssociationExtractor.extract(associations)
              return '' if top_assocs.blank?

              " — #{top_assocs}"
            end
          end

          # Helper class for association formatting following SRP
          class AssociationFormatter
            # Data-driven formatting rules for different type/name combinations
            FORMATTERS = [
              { condition: ->(type, name) { type.nil? && name.nil? }, formatter: ->(*) { '' } },
              { condition: ->(type, _name) { type.nil? }, formatter: ->(_, name) { " :#{name}" } },
              { condition: ->(_type, name) { name.nil? }, formatter: ->(type, _) { "#{type} :" } },
              { condition: ->(type, name) { !type.nil? && !name.nil? }, formatter: ->(type, name) { "#{type} :#{name}" } }
            ].freeze

            def self.call(type, name)
              formatter = FORMATTERS.find { |rule| rule[:condition].call(type, name) }
              formatter[:formatter].call(type, name)
            end
          end

          # Utility class for building columns sections
          class ColumnsSectionBuilder
            def self.build(table_name, schema_tables)
              return '' unless table_name

              cols = ContextSummary.top_columns(schema_tables[table_name])
              return '' unless cols.any?

              " [cols: #{cols.map { |column| "#{column[:name]}:#{column[:type]}" }.join(', ')}]"
            end
          end

          # Utility class for building association count sections
          class AssociationCountBuilder
            def self.build(associations, validations)
              assoc_count = associations.size
              val_count = validations.size
              return '' unless assoc_count.positive? || val_count.positive?

              " (#{assoc_count}a, #{val_count}v)"
            end
          end

          # Utility class for building enum sections
          class EnumSectionBuilder
            def self.build(enum_data)
              enum_names = EnumExtractor.extract(enum_data)
              return '' unless enum_names.any?

              " [enums: #{enum_names.join(', ')}]"
            end
          end

          # Utility class for migration checking
          class MigrationChecker
            def self.recently_migrated?(table_name, migrations)
              ContextSummary.recently_migrated?(table_name, migrations)
            end
          end
        end
      end
    end
  end
end
