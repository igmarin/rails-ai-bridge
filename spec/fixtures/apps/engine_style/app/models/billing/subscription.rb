# rails-ai-bridge: core
class Billing::Subscription < ApplicationRecord
  belongs_to :customer
  has_many :invoices

  validates :plan, :status, presence: true
end
