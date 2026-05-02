# Captures account activity events in the CRM fixture.
class Activity < ApplicationRecord
  belongs_to :account

  validates :kind, presence: true
end
