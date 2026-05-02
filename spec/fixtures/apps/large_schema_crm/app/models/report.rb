# Represents saved operational reports in the CRM fixture.
class Report < ApplicationRecord
  validates :name, :status, presence: true
end
