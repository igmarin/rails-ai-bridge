class Activity < ApplicationRecord
  belongs_to :account

  validates :kind, presence: true
end
