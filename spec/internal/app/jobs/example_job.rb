# frozen_string_literal: true

# Combustion test stack loads without Active Job; keep a plain class so eager_load
# does not reference ActiveJob::Base (see JobIntrospector when Active Job is absent).
class ExampleJob
  def self.perform_later(*)
    # no-op for testing
  end

  def perform(user_id)
    # no-op for testing
  end
end
