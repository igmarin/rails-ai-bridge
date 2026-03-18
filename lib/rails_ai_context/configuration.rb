# frozen_string_literal: true

module RailsAiContext
  class Configuration
    # MCP server settings
    attr_accessor :server_name, :server_version

    # Which introspectors to run (all by default)
    attr_accessor :introspectors

    # Paths to exclude from code search
    attr_accessor :excluded_paths

    # Whether to auto-mount the MCP HTTP endpoint
    attr_accessor :auto_mount

    # HTTP transport settings
    attr_accessor :http_path, :http_bind, :http_port

    # Output directory for generated context files
    attr_accessor :output_dir

    # Models/tables to exclude from introspection
    attr_accessor :excluded_models

    # Maximum depth for association traversal
    attr_accessor :max_association_depth

    # TTL in seconds for cached introspection (default: 30)
    attr_accessor :cache_ttl

    def initialize
      @server_name         = "rails-ai-context"
      @server_version      = RailsAiContext::VERSION
      @introspectors       = %i[schema models routes jobs gems conventions stimulus]
      @excluded_paths      = %w[node_modules tmp log vendor .git]
      @auto_mount          = false
      @http_path           = "/mcp"
      @http_bind           = "127.0.0.1"
      @http_port           = 6029
      @output_dir          = nil # defaults to Rails.root
      @excluded_models     = %w[
        ApplicationRecord
        ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord
        ActionText::RichText ActionText::EncryptedRichText
        ActionMailbox::InboundEmail ActionMailbox::Record
      ]
      @max_association_depth = 2
      @cache_ttl            = 30
    end

    def output_dir_for(app)
      @output_dir || app.root.to_s
    end
  end
end
