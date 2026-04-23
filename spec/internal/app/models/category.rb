# frozen_string_literal: true

# Represents a category that can be assigned to posts
class Category < ApplicationRecord
  has_many :categorizations, dependent: :destroy
  has_many :posts, through: :categorizations
end
