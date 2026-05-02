# rails-ai-bridge: core
class Subscription < ApplicationRecord
  belongs_to :account

  validates :plan, :status, presence: true
end
