# Represents a customer contact in the large-schema CRM fixture.
class Contact < ApplicationRecord
  belongs_to :customer

  validates :name, presence: true
end
