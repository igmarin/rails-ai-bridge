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
      ##
      # Initializes the introspector for a Rails application.
      # Stores the provided Rails application and its root path (as a string) for later introspection.
      # @param [Rails::Application] app - The Rails application instance to inspect.
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
      ##
      # Discovers concrete Ruby classes under app/models that do not inherit from ActiveRecord::Base.
      #
      # The returned hash contains either a `:non_ar_models` array of discovered entries or an `:error` string
      # when introspection fails. Each entry in `:non_ar_models` is a Hash with:
      # - `:name` — the constant name of the class (String)
      # - `:relative_path` — path to the source file relative to the app root (String)
      # - `:tag` — the discovery tag, `"POJO/Service"` (String)
      #
      # @return [Hash] Either:
      #   - `{ non_ar_models: Array<Hash> }` where each Hash has keys `:name`, `:relative_path`, and `:tag`, or
      #   - `{ error: String }` containing a sanitized, truncated error message.
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
      ##
      # Produces a sanitized, truncated error message safe for external exposure.
      # @param [String, nil] message - The original error message which may contain file paths.
      # @return [String] A message with filesystem paths replaced by "/[REDACTED]" and limited to 200 characters; returns "Introspection failed" if the input is nil or empty.
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

      ##
      # Collects discovered non-ActiveRecord classes defined under the given models root.
      # Populates and returns a hash keyed by constant name with metadata for each discovered class.
      # @param [String] models_root - Absolute path to the application's `app/models` directory.
      # @return [Hash{String=>Hash}] A hash mapping class name strings to metadata hashes with keys:
      #   - :name [String] the constant name
      #   - :relative_path [String] the file path relative to the application root
      #   - :tag [String] the discovery tag (e.g., "POJO/Service")
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
      ##
      # Populates the given entries hash with discovered non-ActiveRecord model classes defined under the provided models_root.
      # Iteration errors for individual classes are logged with only the error class name.
      # @param [String] models_root - Absolute path to the application's app/models directory.
      # @param [Hash] entries - Accumulator hash which will be mutated; keys are class names and values are detail hashes.
      # @return [Hash] The same entries hash, populated with discovered non-AR model entries.
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
      ##
      # Determines whether a class is a safe candidate for introspection.
      # Returns `true` only when the class has a non-empty, dot-free constant name that matches `\A[A-Z][A-Za-z0-9_:]*\z` and is not a subclass of `ActiveRecord::Base`.
      # @param [Class] klass - The class to validate.
      # @return [Boolean] `true` if the class meets the naming and inheritance criteria, `false` otherwise (also returns `false` on error).
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

      ##
      # Records a non-ActiveRecord class defined under the application's models directory into the provided entries hash.
      #
      # Only classes that have a valid constant name, do not inherit from `ActiveRecord::Base`,
      # and whose source file is located inside `models_root` are recorded. When recorded,
      # the method sets `entries[name] = { name: name, relative_path: relative_to_root(path), tag: TAG }`.
      # @param [Class] klass - The class to inspect.
      # @param [String] models_root - Absolute path to the `app/models` directory.
      # @param [Hash] entries - Mutable hash that will be populated with discovered entries keyed by class name.
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
