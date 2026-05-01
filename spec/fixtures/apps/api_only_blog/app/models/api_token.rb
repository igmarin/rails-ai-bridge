# Represents bearer token metadata for the API-only fixture.
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, :digest, presence: true
end
