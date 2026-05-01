# Represents invoice records in the billing engine-style fixture.
class Billing::Invoice < ApplicationRecord
  belongs_to :subscription

  validates :number, :status, presence: true
  validates :total, numericality: true
end
