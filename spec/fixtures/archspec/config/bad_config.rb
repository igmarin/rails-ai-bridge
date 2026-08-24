# frozen_string_literal: true

# Violates config.cannot_use :tools — config reaches into the tools layer.
module FixtureConfig
  def self.uses_tool
    FixtureTools::ToolTarget
  end
end
