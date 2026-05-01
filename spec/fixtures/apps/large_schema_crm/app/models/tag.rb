# Represents a label that can be attached through taggings.
class Tag < ApplicationRecord
  has_many :taggings

  validates :name, presence: true
end
