# rails-ai-bridge: core
class Message < ApplicationRecord
  belongs_to :conversation

  validates :author_name, :body, presence: true
  broadcasts_to :conversation
end
