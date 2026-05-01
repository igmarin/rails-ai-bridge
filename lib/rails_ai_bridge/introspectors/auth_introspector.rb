# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers authentication and authorization setup: Devise, Rails 8 auth,
    # Pundit, CanCanCan, CORS, CSP.
    class AuthIntrospector
      attr_reader :app, :path_resolver

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      # Builds a read-only summary of authentication, authorization, and security setup.
      #
      # @return [Hash] authentication, authorization, and browser security metadata
      def call
        {
          authentication: detect_authentication,
          authorization: detect_authorization,
          security: detect_security
        }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def root
        app.root.to_s
      end

      def detect_authentication
        auth = {}

        # Devise
        devise_models = scan_models_for(/devise\s+(.+)$/)
        auth[:devise] = devise_models if devise_models.any?

        # Rails 8 built-in auth
        auth[:rails_auth] = true if model_file_exists?('session.rb') && model_file_exists?('current.rb')

        # has_secure_password
        secure_pw = scan_models_for(/has_secure_password/)
        auth[:has_secure_password] = secure_pw.pluck(:model) if secure_pw.any?

        auth
      end

      def detect_authorization
        authz = {}

        policies = policy_names
        authz[:pundit] = policies if policies.any?

        # CanCanCan
        authz[:cancancan] = true if model_file_exists?('ability.rb')

        authz
      end

      def detect_security
        security = {}

        # CORS
        if gem_present?('rack-cors')
          cors_init = File.join(root, 'config/initializers/cors.rb')
          security[:cors] = { configured: File.exist?(cors_init) }
        end

        # CSP
        csp_init = File.join(root, 'config/initializers/content_security_policy.rb')
        security[:csp] = true if File.exist?(csp_init)

        security
      end

      def scan_models_for(pattern)
        results = []
        path_resolver.files_for('app/models', extension: 'rb').each do |path|
          content = File.read(path)
          matches = content.scan(pattern)
          next if matches.empty?

          model_name = File.basename(path, '.rb').camelize
          results << { model: model_name, matches: matches.flatten.map(&:strip) }
        end
        results.sort_by { |r| r[:model] }
      rescue StandardError
        []
      end

      def gem_present?(name)
        lock_path = File.join(root, 'Gemfile.lock')
        return false unless File.exist?(lock_path)

        File.read(lock_path).include?("    #{name} (")
      rescue StandardError
        false
      end

      def file_exists?(relative_path)
        File.exist?(File.join(root, relative_path))
      end

      def model_file_exists?(relative_path)
        path_resolver.existing_file_for('app/models', relative_path).present?
      end

      def policy_names
        path_resolver.files_for('app/policies', extension: 'rb').map do |file|
          File.basename(file, '.rb').camelize
        end.sort
      rescue StandardError
        []
      end
    end
  end
end
