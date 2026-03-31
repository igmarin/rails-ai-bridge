# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Builds a full markdown document from introspection data.
    # Each section is delegated to a dedicated formatter under {Formatters}.
    # Header and footer can be swapped via constructor injection to produce
    # AI-assistant-specific variants (Claude, Copilot, Codex).
    class MarkdownSerializer
      attr_reader :context

      # @param context [Hash] introspection hash from {Introspector#call}
      # @param header_class [Class] formatter class for the document header (default: {Formatters::HeaderFormatter})
      # @param footer_class [Class] formatter class for the document footer (default: {Formatters::FooterFormatter})
      def initialize(context, header_class: Formatters::HeaderFormatter, footer_class: Formatters::FooterFormatter)
        @context = context
        @header_class = header_class
        @footer_class = footer_class
      end

      # @return [String] full markdown document
      def call
        section_classes.map { |klass| klass.new(context).call }.compact.join("\n\n")
      end

      private

      def section_classes
        [
          @header_class,
          Formatters::AppOverviewFormatter,
          Formatters::SchemaFormatter,
          Formatters::ModelsFormatter,
          Formatters::RoutesFormatter,
          Formatters::JobsFormatter,
          Formatters::GemsFormatter,
          Formatters::ConventionsFormatter,
          Formatters::ControllersFormatter,
          Formatters::ViewsFormatter,
          Formatters::TurboFormatter,
          Formatters::ActiveStorageFormatter,
          Formatters::ActionTextFormatter,
          Formatters::I18nFormatter,
          Formatters::ConfigFormatter,
          Formatters::AssetsFormatter,
          Formatters::AuthFormatter,
          Formatters::ApiFormatter,
          Formatters::TestsFormatter,
          Formatters::RakeTasksFormatter,
          Formatters::DevopsFormatter,
          Formatters::ActionMailboxFormatter,
          Formatters::MigrationsFormatter,
          Formatters::SeedsFormatter,
          Formatters::MiddlewareFormatter,
          Formatters::EnginesFormatter,
          Formatters::MultiDatabaseFormatter,
          @footer_class
        ]
      end
    end
  end
end
