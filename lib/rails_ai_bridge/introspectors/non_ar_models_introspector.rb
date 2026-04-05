# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers concrete Ruby classes under +app/models+ that do not inherit from
    # {ActiveRecord::Base}, so assistants can surface POJOs and service objects that
    # would not appear in ActiveRecord model introspector.
    #
    # After a best-effort eager load (including Zeitwerk +eager_load_dir+ for +app/models+
    # when enabled), entries are derived from +Object.const_source_location+ so anonymous
    # or invalidly named classes are skipped.
    # @since 2.2.0
    class NonArModelsIntrospector
      # Default label attached to each discovered non-AR class in tool and rules output.
      TAG = "POJO/Service"

      # @param app [Rails::Application] host application whose +root+ and paths are used
      # @example Basic usage
      #   introspector = NonArModelsIntrospector.new(Rails.application)
      #   result = introspector.call
      #   result[:non_ar_models] # => [{ name: "OrderCalculator", relative_path: "app/models/order_calculator.rb", tag: "POJO/Service" }]
      def initialize(app)
        @app = app
        @root = app.root.to_s
      end

      # Builds the non-ActiveRecord model index for MCP and static rules.
      #
      # @return [Hash] On success, a hash with key +:non_ar_models+ — an Array of hashes with
      #   keys +:name+ (String), +:relative_path+ (String from app root), and +:tag+ (String, usually the same value as NonArModelsIntrospector::TAG).
      #   On failure, a hash with key +:error+ and a String message.
      # @example Basic usage
      #   introspector = NonArModelsIntrospector.new(Rails.application)
      #   result = introspector.call
      #   result[:non_ar_models] # => [{ name: "OrderCalculator", relative_path: "app/models/order_calculator.rb", tag: "POJO/Service" }]
      def call
        eager_load!
        models_dir = File.join(@root, "app", "models")
        return { non_ar_models: [] } unless Dir.exist?(models_dir)

        models_root = File.expand_path(models_dir)
        entries = collect_entries(models_root)

        { non_ar_models: entries.values.sort_by { |h| h[:name] } }
      rescue StandardError => e
        { error: sanitize_error_message(e.message) }
      end

      # Sanitizes error messages to prevent potential path disclosure
      # @param message [String] The original error message
      # @return [String] Sanitized error message safe for logging
      # @example Sanitizing an error with a file path
      #   sanitize_error_message("Failed to load /path/to/secret/file")
      #   # => "Failed to load /[REDACTED]"
      #   sanitize_error_message("Very long error message that should be truncated...")
      #   # => "Very long error message that should be trunc..."
      def sanitize_error_message(message)
        return "Introspection failed" if message.nil? || message.empty?

        # Remove potential file paths that could expose directory structure
        sanitized = message.gsub(%r{/[^\s]*[/][^/\s]+}, "/[REDACTED]")

        # Limit length to prevent log flooding and information disclosure
        if sanitized.length > 200
          "#{sanitized[0...197]}..."
        else
          sanitized
        end
      end

      private

      def collect_entries(models_root)
        entries = {}
        collect_safe_object_space_entries(models_root, entries)
        entries
      end

      # Safely iterates through ObjectSpace with security boundaries and validation.
      # @param models_root [String] The absolute path to app/models directory
      # @param entries [Hash] Hash to populate with discovered entries
      # @return [Hash] The populated entries hash
      # @example Basic usage
      #   collect_safe_object_space_entries("/path/to/app/models", {})
      #   # => { "OrderCalculator" => { name: "OrderCalculator", relative_path: "app/models/order_calculator.rb", tag: "POJO/Service" } }
      def collect_safe_object_space_entries(models_root, entries)
        ObjectSpace.each_object(Class) do |klass|
          next unless safe_to_process?(klass)

          record_if_non_ar_model(klass, models_root, entries)
        rescue => e
          # Log security-relevant errors without exposing details
          Rails.logger.warn "NonArModelsIntrospector: Error processing class: #{e.class.name}" if defined?(Rails.logger)
        end
        entries
      end

      # Security check before processing a class from ObjectSpace
      # @param klass [Class] The class to validate
      # @return [Boolean] true if safe to process
      # @example Checking if a class is safe
      #   safe_to_process?(OrderCalculator) # => true
      #   safe_to_process?(ActiveRecord::Base) # => false
      def safe_to_process?(klass)
        name = klass.name
        return false if name.nil? || name.empty?
        return false if name.include?(".")
        return false unless name.match?(/\A[A-Z][A-Za-z0-9_:]*\z/)
        return false if klass < ActiveRecord::Base
        true
      rescue => e
        Rails.logger.warn "NonArModelsIntrospector: Error validating class: #{e.class.name}" if defined?(Rails.logger)
        false
      end

      def record_if_non_ar_model(klass, models_root, entries)
        name = klass.name
        return if name.nil? || name.empty?
        return if name.include?(".")
        return unless name.match?(/\A[A-Z][A-Za-z0-9_:]*\z/)
        return if klass < ActiveRecord::Base

        loc = safe_const_source_location(name)
        return unless loc&.first

        path = File.expand_path(loc.first)
        return unless path.start_with?("#{models_root}#{File::SEPARATOR}")

        entries[name] = { name: name, relative_path: relative_to_root(path), tag: TAG }
      end


      def safe_const_source_location(name)
        Object.const_source_location(name)
      rescue ArgumentError, NameError
        nil
      end

      def relative_to_root(abs_path)
        Pathname.new(abs_path).relative_path_from(Pathname.new(@root)).to_s
      end

      def eager_load!
        begin
          Rails.application.eager_load! unless Rails.application.config.eager_load
        rescue StandardError
          nil
        end
        eager_load_app_models_dir
      end

      def eager_load_app_models_dir
        paths = Rails.application.paths["app/models"].to_a
        return if paths.empty?

        dir = paths.first
        return unless dir && Dir.exist?(dir)

        if defined?(Rails.autoloaders) && Rails.autoloaders.respond_to?(:zeitwerk_enabled?) && Rails.autoloaders.zeitwerk_enabled?
          Rails.autoloaders.main.eager_load_dir(dir.to_s)
        end
      rescue StandardError
        nil
      end
    end
  end
end
