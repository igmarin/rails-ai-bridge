# frozen_string_literal: true

# Violates registry.cannot_use :tools — registry reaches into the tools layer.
module FixtureRegistry
  def self.uses_tool
    FixtureTools::ToolTarget
  end
end
