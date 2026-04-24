# frozen_string_literal: true

require 'logger'

module RailsAiBridge
  module Mcp
    # One-line JSON logs for the MCP HTTP Rack path when {Config::Mcp#http_log_json} is enabled.
    # Does not log tokens or Rack +env+ bodies.
    module HttpStructuredLog
      MESSAGE_KEY = 'rails_ai_bridge.mcp.http'

      class << self
        # Emits a single JSON line via +Rails.logger+ (or +$stdout+) when logging is on.
        #
        # @param request [Rack::Request]
        # @param event [Symbol, String] logical outcome (+rate_limited+, +handled+, …); stored as string.
        # @param http_status [Integer]
        # @param extra [Hash] optional extra scalar fields merged into the payload (+nil+ values omitted)
        # @return [void]
        def emit(request:, event:, http_status:, **extra)
          return unless RailsAiBridge.configuration.mcp.http_log_json

          payload = {
            msg: MESSAGE_KEY,
            event: event.to_s,
            http_status: http_status,
            path: request.path,
            client_ip: request.ip.to_s
          }
          rid = request.env['action_dispatch.request_id']
          payload[:request_id] = rid if rid.present?
          extra.each { |k, v| payload[k] = v unless v.nil? }

          target_logger.info(payload.to_json)
        end

        private

        def target_logger
          if defined?(Rails) && Rails.logger
            Rails.logger
          else
            @target_logger ||= Logger.new($stdout)
          end
        end
      end
    end
  end
end
