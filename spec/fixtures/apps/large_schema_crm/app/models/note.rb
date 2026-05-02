# Stores account notes in the large-schema CRM fixture.
class Note < ApplicationRecord
  belongs_to :account

  validates :body, presence: true
end
