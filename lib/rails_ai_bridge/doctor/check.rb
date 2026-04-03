# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    Check = Data.define(:name, :status, :message, :fix)
  end
end
