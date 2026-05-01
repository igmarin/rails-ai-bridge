# rails-ai-bridge: core
class Billing::Customer < ApplicationRecord
  has_many :subscriptions, dependent: :destroy

  validates :email, :name, presence: true
  validates :email, uniqueness: true
end
