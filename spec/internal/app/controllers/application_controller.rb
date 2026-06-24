# frozen_string_literal: true

# Base controller for the test application
# This is the base controller for the entire application,
# providing common functionality for all controllers.
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
end
