# rails-ai-bridge: core
class Billing::Customer < ApplicationRecord
  has_many :subscriptions

  validates :email, :name, presence: true
  validates :email, uniqueness: true
end
