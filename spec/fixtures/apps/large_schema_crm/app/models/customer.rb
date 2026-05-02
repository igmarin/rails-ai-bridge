# rails-ai-bridge: core
class Customer < ApplicationRecord
  belongs_to :account
  has_many :contacts

  validates :email, :name, presence: true
end
