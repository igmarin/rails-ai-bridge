# frozen_string_literal: true

# Cycle leg 1: runtime_context references mcp_transport.
module FixtureRuntime
  def self.uses_transport
    FixtureTransport::ServerTarget
  end
end
