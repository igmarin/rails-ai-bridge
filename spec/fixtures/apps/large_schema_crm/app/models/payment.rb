# Tracks invoice payments in the large-schema CRM fixture.
class Payment < ApplicationRecord
  belongs_to :invoice

  validates :processor, :status, presence: true
end
