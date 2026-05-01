class Payment < ApplicationRecord
  belongs_to :invoice

  validates :processor, :status, presence: true
end
