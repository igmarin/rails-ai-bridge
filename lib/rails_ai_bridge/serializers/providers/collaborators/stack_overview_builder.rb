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
            lines = ['## Stack']
            lines << database_stack_line
            lines << models_stack_line
            lines << ContextSummary.routes_stack_line(@context)
            lines << auth_stack_line
            lines << async_stack_line
            lines << migrations_stack_line
            lines.compact << ''
          end

          private

          # Returns database line or nil if unavailable.
          # @param schema [Hash, nil] Schema hash from context
          # @return [String, nil]
          def database_stack_line(schema = @context[:schema])
            "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables" if schema.is_a?(Hash) && !schema[:error]
          end

          # Returns models count line or nil if unavailable.
          # @param models [Hash, nil] Models hash from context
          # @return [String, nil]
          def models_stack_line(models = @context[:models])
            "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]
          end

          # Returns auth line with detected providers or nil.
          # @param auth [Hash, nil] Auth hash from context
          # @return [String, nil]
          def auth_stack_line(auth = @context[:auth])
            return nil unless auth.is_a?(Hash) && !auth[:error]

            parts = []
            parts << 'Devise' if auth.dig(:authentication, :devise)&.any?
            parts << 'Rails 8 auth' if auth.dig(:authentication, :rails_auth)
            parts << 'Pundit' if auth.dig(:authorization, :pundit)&.any?
            parts << 'CanCanCan' if auth.dig(:authorization, :cancancan)
            "- Auth: #{parts.join(' + ')}" if parts.any?
          end

          # Returns async jobs/mailers/channels line or nil.
          # @param jobs [Hash, nil] Jobs hash from context
          # @return [String, nil]
          def async_stack_line(jobs = @context[:jobs])
            return nil unless jobs.is_a?(Hash) && !jobs[:error]

            job_count = jobs[:jobs]&.size || 0
            mailer_count = jobs[:mailers]&.size || 0
            channel_count = jobs[:channels]&.size || 0
            parts = []
            parts << "#{job_count} jobs" if job_count.positive?
            parts << "#{mailer_count} mailers" if mailer_count.positive?
            parts << "#{channel_count} channels" if channel_count.positive?
            "- Async: #{parts.join(', ')}" if parts.any?
          end

          # Returns migrations line with pending count or nil.
          # @param migrations [Hash, nil] Migrations hash from context
          # @return [String, nil]
          def migrations_stack_line(migrations = @context[:migrations])
            return nil unless migrations.is_a?(Hash) && !migrations[:error]

            pending = migrations[:pending]
            "- Migrations: #{migrations[:total]} total, #{pending&.size || 0} pending"
          end
        end
      end
    end
  end
end
