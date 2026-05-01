class AuditLog < ApplicationRecord
  validates :actor, :event, :record_type, presence: true
end
