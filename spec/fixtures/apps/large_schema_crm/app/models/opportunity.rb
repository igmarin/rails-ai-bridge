# rails-ai-bridge: core
class Opportunity < ApplicationRecord
  belongs_to :account

  validates :name, :stage, presence: true
  scope :open, -> { where.not(stage: "closed") }
end
