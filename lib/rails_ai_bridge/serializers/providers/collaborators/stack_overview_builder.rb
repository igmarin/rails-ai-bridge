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
            def self.build(context)
              sections = [
                '## Stack',
                DatabaseStackBuilder.build(context[:schema]),
                ModelsStackBuilder.build(context[:models]),
                ContextSummary.routes_stack_line(context),
                AuthStackBuilder.build(context[:auth]),
                AsyncStackBuilder.build(context[:jobs]),
                MigrationsStackBuilder.build(context[:migrations])
              ]
              sections.compact << ''
            end
          end

          # Utility class for building database stack lines
          class DatabaseStackBuilder
            def self.build(schema)
              "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables" if schema.is_a?(Hash) && !schema[:error]
            end
          end

          # Utility class for building models stack lines
          class ModelsStackBuilder
            def self.build(models)
              "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]
            end
          end

          # Utility class for building auth stack lines
          class AuthStackBuilder
            def self.build(auth)
              return nil unless auth.is_a?(Hash) && !auth[:error]

              parts = AuthPartsExtractor.extract(auth)
              "- Auth: #{parts.join(' + ')}" if parts.any?
            end
          end

          # Utility class for extracting auth parts
          class AuthPartsExtractor
            AUTH_PROVIDERS = [
              { name: 'Devise', check: ->(auth) { auth.dig(:authentication, :devise)&.any? } },
              { name: 'Rails 8 auth', check: ->(auth) { auth.dig(:authentication, :rails_auth) } },
              { name: 'Pundit', check: ->(auth) { auth.dig(:authorization, :pundit)&.any? } },
              { name: 'CanCanCan', check: ->(auth) { auth.dig(:authorization, :cancancan) } }
            ].freeze

            def self.extract(auth)
              AUTH_PROVIDERS.filter_map { |provider| provider[:name] if provider[:check].call(auth) }
            end
          end

          # Utility class for building async stack lines
          class AsyncStackBuilder
            def self.build(jobs)
              return nil unless jobs.is_a?(Hash) && !jobs[:error]

              parts = AsyncPartsExtractor.extract(jobs)
              "- Async: #{parts.join(', ')}" if parts.any?
            end
          end

          # Utility class for extracting async parts
          class AsyncPartsExtractor
            ASYNC_TYPES = [
              { key: :jobs, label: 'jobs' },
              { key: :mailers, label: 'mailers' },
              { key: :channels, label: 'channels' }
            ].freeze

            def self.extract(jobs)
              ASYNC_TYPES.filter_map do |type|
                count = jobs[type[:key]]&.size || 0
                "#{count} #{type[:label]}" if count.positive?
              end
            end
          end

          # Utility class for building migrations stack lines
          class MigrationsStackBuilder
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
