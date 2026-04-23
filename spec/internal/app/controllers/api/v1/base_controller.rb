# frozen_string_literal: true

# API Version 1 namespace for test application
# :reek:UncommunicativeModuleName
module Api
  module V1
    # Base API controller for V1 endpoints
    class BaseController < ActionController::API
      def index
        render json: { status: "ok" }
      end
    end
  end
end
