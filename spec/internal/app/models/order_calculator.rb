# frozen_string_literal: true

# Plain Ruby object under app/models (not ActiveRecord).
class OrderCalculator
  def self.line_total(cents, quantity)
    cents * quantity
  end
end
