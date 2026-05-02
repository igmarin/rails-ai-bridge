# rails-ai-bridge: core
class Conversation < ApplicationRecord
  has_many :messages

  validates :title, presence: true
  scope :open, -> { where(status: "open") }
end
