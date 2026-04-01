# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Config::Server do
  subject(:server) { described_class.new }

  it "defaults server_name to 'rails-ai-bridge'" do
    expect(server.server_name).to eq("rails-ai-bridge")
  end

  it "defaults server_version to the gem VERSION" do
    expect(server.server_version).to eq(RailsAiBridge::VERSION)
  end

  it "defaults http_path to '/mcp'" do
    expect(server.http_path).to eq("/mcp")
  end

  it "defaults http_bind to '127.0.0.1'" do
    expect(server.http_bind).to eq("127.0.0.1")
  end

  it "defaults http_port to 6029" do
    expect(server.http_port).to eq(6029)
  end

  it "defaults auto_mount to false" do
    expect(server.auto_mount).to eq(false)
  end

  it "defaults additional_tools to []" do
    expect(server.additional_tools).to eq([])
  end

  it "defaults additional_resources to {}" do
    expect(server.additional_resources).to eq({})
  end

  it "allows setting server_name" do
    server.server_name = "my-app"
    expect(server.server_name).to eq("my-app")
  end

  it "allows setting http_port" do
    server.http_port = 9000
    expect(server.http_port).to eq(9000)
  end
end
