class Report < ApplicationRecord
  validates :name, :status, presence: true
end
