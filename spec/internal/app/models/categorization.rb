# frozen_string_literal: true

# Join model connecting posts to categories
class Categorization < ApplicationRecord
  belongs_to :post
  belongs_to :category
end
