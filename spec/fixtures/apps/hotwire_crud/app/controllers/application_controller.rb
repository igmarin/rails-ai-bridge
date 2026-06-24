# frozen_string_literal: true

# Base browser controller for the Hotwire CRUD fixture.
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
end
