# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds introspector selection, exclusion rules, and caching settings.
    class Introspection
      # @return [Array<Symbol>] active introspector keys
      attr_reader :introspectors

      # Resets the tracked preset name to +nil+ when introspectors are assigned directly.
      # This ensures {#preset} returns +nil+ after +config.introspectors = [...]+ or
      # +config.introspectors += %i[...]+, since the list no longer matches a named preset.
      #
      # @param value [Array<Symbol>]
      # @return [Array<Symbol>] the assigned introspector list
      def introspectors=(value)
        @preset = nil
        @introspectors = value
      end

      # @return [Array<String>] directory names excluded from code search
      attr_accessor :excluded_paths

      # @return [Array<String>] model class names excluded from introspection
      attr_accessor :excluded_models

      # @return [Array<String>] model class names tagged as +core_entity+ in semantic classification (AI focus)
      attr_accessor :core_models

      # @return [Array<String>] table names/patterns excluded from schema introspection
      attr_accessor :excluded_tables

      # @return [Array<Symbol>] product-level category keys that subtract introspectors at runtime
      attr_accessor :disabled_introspection_categories

      # @return [Integer] TTL in seconds for cached introspection results
      attr_accessor :cache_ttl

      # @return [Boolean] include credential key names in config introspection output
      attr_accessor :expose_credentials_key_names

      # @return [Hash{Symbol => Class}] additional custom introspector classes
      attr_accessor :additional_introspectors

      # @return [Array<String>] extra file extensions allowed for rails_search_code
      attr_accessor :search_code_allowed_file_types

      # @return [Integer] maximum +pattern+ size in bytes for {Tools::SearchCode} (ReDoS / abuse guard)
      attr_accessor :search_code_pattern_max_bytes

      # @return [Float] seconds before {Tools::SearchCode} aborts (+0+ disables the timeout)
      attr_accessor :search_code_timeout_seconds

      ##
      # Initializes Introspection configuration with sensible defaults.
      # Sets:
      # - @introspectors to a duplicate of Configuration::PRESETS[:standard]
      # - @preset to :standard, matching the default introspector list
      # - @excluded_paths to ["node_modules", "tmp", "log", "vendor", ".git"]
      # - @excluded_models to common Rails/ActiveStorage/Action* classes
      # - @core_models, @excluded_tables, and @disabled_introspection_categories to empty arrays
      # - @cache_ttl to 30
      # - @expose_credentials_key_names to false
      # - @additional_introspectors to an empty hash
      # - @search_code_allowed_file_types to an empty array
      # - @search_code_pattern_max_bytes to 2048
      # - @search_code_timeout_seconds to 5.0
      #
      def initialize
        @introspectors      = Configuration::PRESETS[:standard].dup
        @preset             = :standard
        @excluded_paths     = %w[node_modules tmp log vendor .git]
        @excluded_models    = %w[
          ApplicationRecord
          ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord
          ActionText::RichText ActionText::EncryptedRichText
          ActionMailbox::InboundEmail ActionMailbox::Record
        ]
        @core_models                       = []
        @excluded_tables                   = []
        @disabled_introspection_categories = []
        @cache_ttl                         = 30
        @expose_credentials_key_names      = false
        @additional_introspectors          = {}
        @search_code_allowed_file_types    = []
        @search_code_pattern_max_bytes     = 2048
        @search_code_timeout_seconds       = 5.0
      end

      # Switch the active introspector list to a named preset.
      #
      # @param name [Symbol, String] preset key from {Configuration::PRESETS}
      # @raise [ArgumentError] when the preset is unknown
      def preset=(name)
        name = name.to_sym
        raise ArgumentError, "Unknown preset: #{name}. Valid presets: #{Configuration::PRESETS.keys.join(', ')}" unless Configuration::PRESETS.key?(name)

        self.introspectors = Configuration::PRESETS[name].dup
        @preset = name
      end

      # Returns the active preset name, or +nil+ if introspectors were modified directly.
      #
      # @return [Symbol, nil] The preset name, or nil for modified configurations
      attr_reader :preset

      # Introspectors after removing those disabled by {#disabled_introspection_categories}.
      #
      # @return [Array<Symbol>]
      def effective_introspectors
        disabled = @disabled_introspection_categories.flat_map do |c|
          Configuration::INTROSPECTION_CATEGORY_INTROSPECTORS[c.to_sym] || []
        end.uniq
        @introspectors.reject { |i| disabled.include?(i) }
      end

      # Whether a table name matches any {#excluded_tables} pattern (exact or glob).
      #
      # @param table_name [String, nil]
      # @return [Boolean]
      def excluded_table?(table_name)
        return false if table_name.nil? || table_name.to_s.empty?

        @excluded_tables.any? { |pat| ExclusionHelper.table_pattern_match?(pat.to_s, table_name.to_s) }
      end
    end
  end
end
