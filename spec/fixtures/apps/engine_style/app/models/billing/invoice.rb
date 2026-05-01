class Billing::Invoice < ApplicationRecord
  belongs_to :subscription

  validates :number, :total, :status, presence: true
end
