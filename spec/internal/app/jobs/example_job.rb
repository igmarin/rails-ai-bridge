# frozen_string_literal: true

# Combustion test stack loads without Active Job; keep a plain class so eager_load
# does not reference ActiveJob::Base (see JobIntrospector when Active Job is absent).
class ExampleJob
  def self.perform_later(*)
    # no-op for testing
  end

  ##
  # Performs the job for the given user id (no-op stub used for tests).
  # @param [Object] user_id - The ID of the user.
  def perform(user_id)
    # no-op for testing
  end
end
