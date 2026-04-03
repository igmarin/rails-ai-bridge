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
      # @param header_class [Class] formatter class for the document header (default: {Formatters::Providers::HeaderFormatter})
      # @param footer_class [Class] formatter class for the document footer (default: {Formatters::Providers::FooterFormatter})
      def initialize(context, header_class: Formatters::Providers::HeaderFormatter, footer_class: Formatters::Providers::FooterFormatter)
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
          Formatters::Sections::AppOverviewFormatter,
          Formatters::Sections::SchemaFormatter,
          Formatters::Sections::ModelsFormatter,
          Formatters::Sections::RoutesFormatter,
          Formatters::Sections::JobsFormatter,
          Formatters::Sections::GemsFormatter,
          Formatters::Sections::ConventionsFormatter,
          Formatters::Sections::ControllersFormatter,
          Formatters::Sections::ViewsFormatter,
          Formatters::Sections::TurboFormatter,
          Formatters::Sections::ActiveStorageFormatter,
          Formatters::Sections::ActionTextFormatter,
          Formatters::Sections::I18nFormatter,
          Formatters::Sections::ConfigFormatter,
          Formatters::Sections::AssetsFormatter,
          Formatters::Sections::AuthFormatter,
          Formatters::Sections::ApiFormatter,
          Formatters::Sections::TestsFormatter,
          Formatters::Sections::RakeTasksFormatter,
          Formatters::Sections::DevopsFormatter,
          Formatters::Sections::ActionMailboxFormatter,
          Formatters::Sections::MigrationsFormatter,
          Formatters::Sections::SeedsFormatter,
          Formatters::Sections::MiddlewareFormatter,
          Formatters::Sections::EnginesFormatter,
          Formatters::Sections::MultiDatabaseFormatter,
          @footer_class
        ]
      end
    end
  end
end
