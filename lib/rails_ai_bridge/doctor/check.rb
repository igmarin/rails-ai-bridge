# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    # Immutable result row for a single diagnostic check.
    #
    # @!attribute [r] name
    #   @return [String] short label shown in reports (e.g. "Schema")
    # @!attribute [r] status
    #   @return [Symbol] +:pass+, +:warn+, or +:fail+
    # @!attribute [r] message
    #   @return [String] human-readable outcome
    # @!attribute [r] fix
    #   @return [String, nil] suggested remediation when not +:pass+
    Check = Data.define(:name, :status, :message, :fix)
  end
end
