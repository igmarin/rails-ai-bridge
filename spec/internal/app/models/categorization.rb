# frozen_string_literal: true

class Categorization < ApplicationRecord
  belongs_to :post
  belongs_to :category
end
