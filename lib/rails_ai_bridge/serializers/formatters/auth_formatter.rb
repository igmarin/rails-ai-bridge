# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Authentication & Authorization section (Devise, Pundit, etc.).
      class AuthFormatter < SectionFormatter
        section :auth

        private

        def render(data)
          authn = data[:authentication] || {}
          authz = data[:authorization] || {}
          return if authn.empty? && authz.empty?

          lines = [ "## Authentication & Authorization" ]
          if authn[:devise]
            lines << "### Devise"
            authn[:devise].each { |d| lines << "- `#{d[:model]}`: #{d[:matches].join(', ')}" }
          end
          lines << "- Rails 8 built-in auth detected" if authn[:rails_auth]
          lines << "- has_secure_password: #{authn[:has_secure_password].join(', ')}" if authn[:has_secure_password]
          if authz[:pundit]
            lines << "### Pundit Policies"
            authz[:pundit].each { |p| lines << "- `#{p}`" }
          end
          lines << "- CanCanCan: Ability class detected" if authz[:cancancan]
          lines.join("\n")
        end
      end
    end
  end
end
