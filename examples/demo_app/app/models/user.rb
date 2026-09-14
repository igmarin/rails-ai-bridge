# frozen_string_literal: true

# rails-ai-bridge: core
class User < ApplicationRecord
  has_many :posts, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  scope :recent, -> { order(created_at: :desc) }
end
