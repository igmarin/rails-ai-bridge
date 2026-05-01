# rails-ai-bridge: core
class Article < ApplicationRecord
  belongs_to :user

  validates :title, :body, presence: true
  scope :published, -> { where(status: "published") }
end
