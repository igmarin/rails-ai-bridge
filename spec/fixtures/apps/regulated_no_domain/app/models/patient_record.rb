class PatientRecord < ApplicationRecord
  validates :external_reference, :ssn_digest, presence: true
end
