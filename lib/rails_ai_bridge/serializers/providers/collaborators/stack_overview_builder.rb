# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds the stack overview section for AI context documents.
        # Extracts and formats database, models, routes, auth, async jobs, and migrations information.
        class StackOverviewBuilder
          # @param context [Hash] Introspection context hash
          def initialize(context)
            @context = context
          end

          # Renders the complete stack overview section.
          # Includes database adapter/table count, model count, routes, auth gems,
          # async jobs/mailers/channels, and pending migrations when available.
          # Silently skips any sub-section whose context key is missing or has an +:error+ key.
          #
          # @return [Array<String>] Lines for the stack overview section, always non-empty
          def build
            StackSectionBuilder.build(@context)
          end

          # Utility class for building complete stack sections
          class StackSectionBuilder
            # Builds complete stack overview section
            # @param context [Hash] Introspection context hash
            # @return [Array<String>] Complete stack section lines
            def self.build(context)
              sections = [
                '## Stack',
                DatabaseStackBuilder.build(context),
                ModelsStackBuilder.build(context[:models]),
                ContextSummary.routes_stack_line(context),
                RouteFocusStackBuilder.build(context),
                AuthStackBuilder.build(context[:auth]),
                AsyncStackBuilder.build(context[:jobs]),
                MigrationsStackBuilder.build(context[:migrations])
              ]
              sections.compact << ''
            end
          end

          # Utility class for building database stack lines
          class DatabaseStackBuilder
            # Builds database information line
            # @param context_or_schema [Hash, nil] full context or schema hash
            # @return [String, nil] Database line or nil if unavailable
            def self.build(context_or_schema)
              schema = schema_from(context_or_schema)
              return nil unless schema.is_a?(Hash) && !schema[:error] && !schema[:skipped]

              "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables#{hot_table_suffix(context_or_schema)}"
            end

            def self.schema_from(context_or_schema)
              return nil unless context_or_schema.is_a?(Hash)

              context_or_schema.key?(:schema) ? context_or_schema[:schema] : context_or_schema
            end

            def self.hot_table_names(context)
              DatabaseStatsSummary.new(context).hot_table_names
            end

            def self.hot_table_suffix(context)
              hot_tables = hot_table_names(context)
              hot_tables.any? ? " — hot/large: #{hot_tables.join(', ')}" : ''
            end

            private_class_method :schema_from, :hot_table_names, :hot_table_suffix

            # Extracts bounded hot-table hints from optional database stats.
            class DatabaseStatsSummary
              def initialize(context)
                @context = context
              end

              # @return [Array<String>] up to three large/hot table names
              def hot_table_names
                return [] unless stats_available?

                Array(stats[:tables]).filter_map do |row|
                  bucket = row[:size_bucket] || ContextSummary.database_size_bucket(row[:approximate_rows])
                  row[:table] if %w[large hot].include?(bucket)
                end.first(3)
              end

              private

              def stats_available?
                @context.is_a?(Hash) && stats.is_a?(Hash) && !stats[:error] && !stats[:skipped]
              end

              def stats
                @context[:database_stats] if @context.is_a?(Hash)
              end
            end
            private_constant :DatabaseStatsSummary
          end

          # Utility class for building models stack lines
          class ModelsStackBuilder
            # Builds models count line
            # @param models [Hash, nil] Models hash from context
            # @return [String, nil] Models line or nil if unavailable
            def self.build(models)
              "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]
            end
          end

          # Utility class for building bounded route-focus stack line
          class RouteFocusStackBuilder
            # @param context [Hash] Introspection context hash
            # @return [String, nil] Endpoint focus summary or nil if unavailable
            def self.build(context)
              focus = ContextSummary.route_focus_lines(context, limit: 3)
              return nil if focus.empty?

              "- Endpoint focus: #{focus.map { |line| line.delete_prefix('- ') }.join('; ')}"
            end
          end

          # Utility class for building auth stack lines
          class AuthStackBuilder
            # Builds authentication providers line
            # @param auth [Hash, nil] Auth hash from context
            # @return [String, nil] Auth line or nil if unavailable
            def self.build(auth)
              return nil unless auth.is_a?(Hash) && !auth[:error]

              parts = AuthPartsExtractor.extract(auth)
              "- Auth: #{parts.join(' + ')}" if parts.any?
            end
          end

          # Utility class for extracting auth provider parts
          class AuthPartsExtractor
            # Authentication providers configuration
            AUTH_PROVIDERS = [
              { name: 'Devise', section: :authentication, key: :devise },
              { name: 'Rails 8 auth', section: :authentication, key: :rails_auth },
              { name: 'Pundit', section: :authorization, key: :pundit },
              { name: 'CanCanCan', section: :authorization, key: :cancancan }
            ].freeze

            # Extracts available authentication providers
            # @param auth [Hash] Auth configuration hash
            # @return [Array<String>] List of provider names
            def self.extract(auth)
              payload = AuthPayload.new(auth)
              AUTH_PROVIDERS.filter_map do |provider|
                provider[:name] if payload.provider_present?(provider[:section], provider[:key])
              end
            end

            # Normalizes nested auth provider payloads before probing them.
            class AuthPayload
              # @param auth [Hash] Auth configuration hash
              def initialize(auth)
                @auth = auth
              end

              # @param section_name [Symbol] auth payload section name
              # @param provider_key [Symbol] provider key inside the section
              # @return [Boolean] true when the provider payload is populated
              def provider_present?(section_name, provider_key)
                section(section_name)[provider_key].present?
              end

              private

              def section(name)
                payload = @auth[name]
                payload.is_a?(Hash) ? payload : {}
              end
            end
          end

          # Utility class for building async stack lines
          class AsyncStackBuilder
            # Builds async components line
            # @param jobs [Hash, nil] Jobs hash from context
            # @return [String, nil] Async line or nil if unavailable
            def self.build(jobs)
              return nil unless jobs.is_a?(Hash) && !jobs[:error]

              parts = AsyncPartsExtractor.extract(jobs)
              "- Async: #{parts.join(', ')}" if parts.any?
            end
          end

          # Utility class for extracting async component parts
          class AsyncPartsExtractor
            # Async component types configuration
            ASYNC_TYPES = [
              { key: :jobs, label: 'jobs' },
              { key: :mailers, label: 'mailers' },
              { key: :channels, label: 'channels' }
            ].freeze

            # Extracts available async components
            # @param jobs [Hash] Jobs configuration hash
            # @return [Array<String>] List of component descriptions
            def self.extract(jobs)
              ASYNC_TYPES.filter_map do |type|
                count = jobs[type[:key]]&.size || 0
                "#{count} #{type[:label]}" if count.positive?
              end
            end
          end

          # Utility class for building migrations stack lines
          class MigrationsStackBuilder
            # Builds migrations information line
            # @param migrations [Hash, nil] Migrations hash from context
            # @return [String, nil] Migrations line or nil if unavailable
            def self.build(migrations)
              return nil unless migrations.is_a?(Hash) && !migrations[:error]

              pending = migrations[:pending]
              "- Migrations: #{migrations[:total]} total, #{pending&.size || 0} pending"
            end
          end
        end
      end
    end
  end
end
