# rails-ai-bridge: core
class Account < ApplicationRecord
  has_many :customers
  has_many :opportunities
  has_many :invoices
  has_many :subscriptions
  has_many :activities
  has_many :notes
  has_many :tasks

  validates :name, presence: true
end
