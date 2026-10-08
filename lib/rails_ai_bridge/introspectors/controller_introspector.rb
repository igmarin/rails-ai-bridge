# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers controllers and extracts filters, strong params,
    # respond_to formats, concerns, actions, and API detection.
    class ControllerIntrospector
      attr_reader :app, :config

      # Initializes the controller introspector and path resolver.
      #
      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @config = RailsAiBridge.configuration
        @path_resolver = PathResolver.new(app)
      end

      def call
        eager_load_controllers!
        controllers = discover_controllers

        result = controllers.each_with_object({}) do |ctrl, hash|
          hash[ctrl.name] = extract_controller_details(ctrl)
        rescue StandardError => error
          Rails.logger.debug { "CTRL ERROR: #{error.message}" }
          hash[ctrl.name] = { error: error.message }
        end

        { controllers: result }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def eager_load_controllers!
        @app.eager_load! unless @app.config.eager_load
      rescue StandardError
        nil
      end

      def discover_controllers
        return [] unless defined?(ActionController::Base)

        bases = [ActionController::Base]
        bases << ActionController::API if defined?(ActionController::API)

        bases.flat_map(&:descendants).reject do |ctrl|
          ctrl.name.nil? || ctrl.name == 'ApplicationController' ||
            ctrl.name.start_with?('Rails::', 'ActionMailbox::', 'ActiveStorage::') ||
            excluded_controller?(ctrl)
        end.uniq.sort_by(&:name)
      end

      # @param ctrl [Class]
      # @return [Boolean]
      def excluded_controller?(ctrl)
        ExclusionHelper.excluded_class_or_table?(ctrl.name, config)
      end

      def extract_controller_details(ctrl)
        source = read_source(ctrl)
        strong_params = extract_strong_params(source)
        respond_to_formats = extract_respond_to(source)

        {
          parent_class: ctrl.superclass.name,
          api_controller: api_controller?(ctrl),
          actions: extract_actions(ctrl),
          filters: FilterExtractor.new(ctrl).call,
          concerns: extract_concerns(ctrl),
          strong_params: strong_params,
          strong_params_provenance: strong_params_provenance(ctrl, strong_params),
          respond_to_formats: respond_to_formats,
          respond_to_formats_provenance: (:regex if respond_to_formats.any?)
        }.compact
      end

      def api_controller?(ctrl)
        return true if defined?(ActionController::API) && ctrl.ancestors.include?(ActionController::API)

        false
      end

      def extract_actions(ctrl)
        ctrl.action_methods.to_a.sort
      rescue StandardError
        []
      end

      def extract_concerns(ctrl)
        ctrl.ancestors
            .select { |mod| mod.is_a?(Module) && !mod.is_a?(Class) }
            .reject do |mod|
          mod.name&.start_with?('ActionController', 'ActionDispatch', 'ActiveSupport',
                                'AbstractController')
        end
          .filter_map(&:name)
      rescue StandardError
        []
      end

      def extract_strong_params(source)
        return [] if source.nil?

        source.scan(/def\s+(\w+_params)\b/).flatten.uniq
      end

      def extract_respond_to(source)
        return [] if source.nil?
        return [] unless source.match?(/respond_to\s+do/)

        source.scan(/format\.(\w+)/).flatten.uniq.sort
      end

      # @return [Symbol, nil] +:prism+ when Prism confirms every strong-params method, +:regex+
      #   when it does not, and nil when the controller has no strong-params methods
      def strong_params_provenance(ctrl, strong_params)
        return if strong_params.empty?

        scanner = prism_scanner
        return :regex unless scanner

        StrongParamsProvenance.new(scanner, source_path(ctrl), ctrl.name).call(strong_params)
      end

      # One scanner per run, so +prism_max_files+ caps every controller scanned in that run.
      #
      # @return [StaticPrismScanner, nil] nil unless +prism_enabled+ is on
      def prism_scanner
        return unless config.prism_enabled

        @prism_scanner ||= StaticPrismScanner.new(max_files: config.prism_max_files)
      end

      def read_source(ctrl)
        path = source_path(ctrl)
        return nil unless path && File.exist?(path)

        File.read(path)
      rescue StandardError
        nil
      end

      # Resolves a controller source file from the configured logical +app/controllers+ path.
      #
      # @param ctrl [Class] controller class
      # @return [String, nil] absolute source path when present
      def source_path(ctrl)
        underscored = ctrl.name.underscore
        @path_resolver.existing_file_for('app/controllers', "#{underscored}.rb")
      end
    end
  end
end
