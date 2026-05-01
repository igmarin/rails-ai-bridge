# Records audit events for the large-schema CRM fixture.
class AuditLog < ApplicationRecord
  validates :actor, :event, :record_type, presence: true
end
