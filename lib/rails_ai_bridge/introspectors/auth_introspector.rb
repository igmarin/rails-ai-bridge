# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers authentication and authorization setup: Devise, Rails 8 auth,
    # Pundit, CanCanCan, CORS, CSP.
    class AuthIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

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
        auth[:rails_auth] = true if file_exists?('app/models/session.rb') && file_exists?('app/models/current.rb')

        # has_secure_password
        secure_pw = scan_models_for(/has_secure_password/)
        auth[:has_secure_password] = secure_pw.pluck(:model) if secure_pw.any?

        auth
      end

      def detect_authorization
        authz = {}

        # Pundit
        policies_dir = File.join(root, 'app/policies')
        if Dir.exist?(policies_dir)
          policies = Dir.glob(File.join(policies_dir, '**/*.rb')).map do |f|
            File.basename(f, '.rb').camelize
          end.sort
          authz[:pundit] = policies if policies.any?
        end

        # CanCanCan
        ability_path = File.join(root, 'app/models/ability.rb')
        authz[:cancancan] = true if File.exist?(ability_path)

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
        models_dir = File.join(root, 'app/models')
        return [] unless Dir.exist?(models_dir)

        results = []
        Dir.glob(File.join(models_dir, '**/*.rb')).each do |path|
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
    end
  end
end
