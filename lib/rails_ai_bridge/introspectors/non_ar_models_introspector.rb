# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers concrete Ruby classes under the logical +app/models+ Rails path that do not inherit from
    # {ActiveRecord::Base}, so assistants can surface POJOs and service objects that
    # would not appear in ActiveRecord model introspector.
    #
    # After a best-effort eager load of every configured +app/models+ directory,
    # entries are derived from +Object.const_source_location+ so anonymous or
    # invalidly named classes are skipped.
    # @since 2.2.0
    class NonArModelsIntrospector
      # Default label attached to each discovered non-AR class in tool and rules output.
      TAG = 'POJO/Service'

      CollectionContext = Struct.new(:models_root, :rows, keyword_init: true)
      private_constant :CollectionContext

      # Initializes the introspector for a Rails application.
      #
      # Stores the provided Rails application, its root path, and a path resolver
      # that maps configured model directories back to stable logical paths.
      #
      # @param app [Rails::Application] host application whose +root+ and paths are used
      def initialize(app)
        @app = app
        @root = app.root.to_s
        @path_resolver = PathResolver.new(app)
      end

      # Builds the non-ActiveRecord model index for MCP and static rules.
      #
      # Discovery uses every configured +app/models+ path rather than assuming
      # the conventional directory exists.
      #
      # @return [Hash] Either:
      #   - `{ non_ar_models: Array<Hash> }` where each Hash has keys `:name`, `:relative_path`, and `:tag`, or
      #   - `{ error: String }` containing a sanitized, truncated error message.
      def call
        eager_load!
        models_roots = models_roots_for_discovery
        return { non_ar_models: [] } if models_roots.empty?

        entries = {}
        models_roots.each { |models_root| collect_entries(models_root, entries) }

        { non_ar_models: entries.values.sort_by { |h| h[:name] } }
      rescue StandardError => error
        { error: sanitize_error_message(error.message) }
      end

      # Produces a sanitized, truncated error message safe for external exposure.
      #
      # @param [String, nil] message - The original error message which may contain file paths.
      # @return [String] A message with filesystem paths replaced by "/[REDACTED]" and limited to 200 characters; returns "Introspection failed" if the input is nil or empty.
      def sanitize_error_message(message)
        return 'Introspection failed' if message.blank?

        # Remove potential file paths that could expose directory structure
        sanitized = message.gsub(%r{/[^\s]*/[^/\s]+}, '/[REDACTED]')

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
      # @param [Hash] entries - Optional accumulator keyed by constant name.
      # @return [Hash{String=>Hash}] A hash mapping class name strings to metadata hashes with keys:
      #   - :name [String] the constant name
      #   - :relative_path [String] the file path relative to the application root
      #   - :tag [String] the discovery tag (e.g., "POJO/Service")
      def collect_entries(models_root, entries = {})
        context = CollectionContext.new(models_root: models_root, rows: entries)

        ObjectSpace.each_object(Class) do |klass|
          collect_entry(klass, context)
        end
        entries
      end

      # Safely processes one ObjectSpace class candidate for a models root.
      #
      # @param klass [Class] class candidate from ObjectSpace
      # @param context [CollectionContext] collection state for the current models root
      # @return [void]
      def collect_entry(klass, context)
        return unless safe_to_process?(klass)

        record_if_non_ar_model(klass, context)
      rescue StandardError => error
        logger = Rails.logger if defined?(Rails)
        logger&.warn "NonArModelsIntrospector: Error processing class: #{error.class.name}"
      end

      # Determines whether a class is a safe candidate for introspection.
      #
      # Returns `true` only when the class has a non-empty, dot-free constant name that matches `\A[A-Z][A-Za-z0-9_:]*\z` and is not a subclass of `ActiveRecord::Base`.
      # @param [Class] klass - The class to validate.
      # @return [Boolean] `true` if the class meets the naming and inheritance criteria, `false` otherwise (also returns `false` on error).
      def safe_to_process?(klass)
        name = klass.name
        return false if name.blank?
        return false if name.include?('.')
        return false unless name.match?(/\A[A-Z][A-Za-z0-9_:]*\z/)
        return false if klass < ActiveRecord::Base

        true
      rescue StandardError => error
        Rails.logger.warn "NonArModelsIntrospector: Error validating class: #{error.class.name}" if defined?(Rails.logger)
        false
      end

      ##
      # Records a non-ActiveRecord class defined under the application's models directory into the provided entries hash.
      #
      # Only classes that have a valid constant name, do not inherit from `ActiveRecord::Base`,
      # and whose source file is located inside `models_root` are recorded. When recorded,
      # the method sets `entries[name] = { name: name, relative_path: logical_model_path(path), tag: TAG }`.
      # @param [Class] klass - The class to inspect.
      # @param [CollectionContext] context - Collection state with the models root and mutable entries hash.
      def record_if_non_ar_model(klass, context)
        name = klass.name
        return if name.blank?
        return if name.include?('.')
        return unless name.match?(/\A[A-Z][A-Za-z0-9_:]*\z/)
        return if klass < ActiveRecord::Base

        loc = safe_const_source_location(name)
        return unless loc&.first

        path = File.expand_path(loc.first)
        return unless path.start_with?("#{context.models_root}#{File::SEPARATOR}")

        context.rows[name] = { name: name, relative_path: logical_model_path(path), tag: TAG }
      end

      def safe_const_source_location(name)
        Object.const_source_location(name)
      rescue ArgumentError, NameError
        nil
      end

      # Maps a discovered source file to the logical +app/models+ path shown in
      # generated context, even when the filesystem path is custom configured.
      #
      # @param abs_path [String] absolute source path
      # @return [String] stable logical context path
      def logical_model_path(abs_path)
        @path_resolver.logical_file_path(abs_path, logical_path: 'app/models')
      end

      # Eager-loads application code and every configured model directory on a
      # best-effort basis before ObjectSpace discovery.
      #
      # @return [void]
      def eager_load!
        begin
          @app.eager_load! unless @app.config.eager_load
        rescue StandardError
          nil
        end
        eager_load_app_models_dir
      end

      # Eager-loads each configured +app/models+ directory through Zeitwerk when available.
      #
      # @return [void]
      def eager_load_app_models_dir
        if defined?(Rails.autoloaders) && Rails.autoloaders.respond_to?(:zeitwerk_enabled?) && Rails.autoloaders.zeitwerk_enabled?
          models_roots_for_discovery.each { |dir| Rails.autoloaders.main.eager_load_dir(dir.to_s) }
        end
      rescue StandardError
        nil
      end

      # Returns existing configured model directories for non-AR class discovery.
      #
      # @return [Array<String>] absolute +app/models+ directory paths
      def models_roots_for_discovery
        @path_resolver.directories_for('app/models')
                      .select { |dir| Dir.exist?(dir) }
                      .map { |dir| File.expand_path(dir) }
      end
    end
  end
end
