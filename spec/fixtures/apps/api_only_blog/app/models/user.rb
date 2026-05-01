# rails-ai-bridge: core
class User < ApplicationRecord
  has_many :articles
  has_many :api_tokens

  validates :email, presence: true
end
