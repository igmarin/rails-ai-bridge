# Represents billable products in the large-schema CRM fixture.
class Product < ApplicationRecord
  has_many :invoice_lines

  validates :name, :sku, presence: true
end
