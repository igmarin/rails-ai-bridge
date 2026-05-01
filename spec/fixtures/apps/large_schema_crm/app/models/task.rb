class Task < ApplicationRecord
  belongs_to :account

  validates :title, :status, presence: true
end
