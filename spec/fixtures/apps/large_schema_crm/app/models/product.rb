class Product < ApplicationRecord
  has_many :invoice_lines

  validates :name, :sku, presence: true
end
