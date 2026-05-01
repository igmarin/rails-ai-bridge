# rails-ai-bridge: core
class Invoice < ApplicationRecord
  belongs_to :account
  has_many :invoice_lines
  has_many :payments

  validates :number, :status, presence: true
end
