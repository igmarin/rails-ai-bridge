# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class BridgeMetadataChecker < BaseChecker
        def call
          check(
            "Bridge metadata",
            RailsAiBridge::Resources.resource_definitions.key?("rails://bridge/meta"),
            pass: { message: "rails://bridge/meta available for bridge diagnostics" },
            fail: { status: :fail, message: "rails://bridge/meta resource is missing", fix: "Register the bridge metadata resource in `RailsAiBridge::Resources`" }
          )
        end
      end
    end
  end
end
