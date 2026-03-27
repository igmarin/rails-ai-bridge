# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RailsAiBridge::VERSION" do
  specify do
    expect(RailsAiBridge::VERSION).to be_a(String)
    expect(RailsAiBridge::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
