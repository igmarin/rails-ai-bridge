# Represents redacted patient metadata in the regulated fixture.
class PatientRecord < ApplicationRecord
  validates :external_reference, :ssn_digest, presence: true
end
