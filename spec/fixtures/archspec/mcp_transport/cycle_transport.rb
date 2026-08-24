# frozen_string_literal: true

# Cycle leg 2: mcp_transport references runtime_context, closing the cycle.
module FixtureTransport
  class ServerTarget
    def self.uses_runtime
      FixtureRuntime
    end
  end
end
