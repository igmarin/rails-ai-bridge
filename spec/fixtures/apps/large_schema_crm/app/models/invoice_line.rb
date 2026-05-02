# Joins invoices to products in the large-schema CRM fixture.
class InvoiceLine < ApplicationRecord
  belongs_to :invoice
  belongs_to :product
end
