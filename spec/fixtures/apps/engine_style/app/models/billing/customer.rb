# rails-ai-bridge: core
class Billing::Customer < ApplicationRecord
  has_many :subscriptions

  validates :email, :name, presence: true
end
