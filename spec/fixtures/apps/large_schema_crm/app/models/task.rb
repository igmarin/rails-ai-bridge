# Tracks account work items in the large-schema CRM fixture.
class Task < ApplicationRecord
  belongs_to :account

  validates :title, :status, presence: true
end
