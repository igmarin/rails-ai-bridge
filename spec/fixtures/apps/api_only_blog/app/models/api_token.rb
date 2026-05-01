class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, :digest, presence: true
end
