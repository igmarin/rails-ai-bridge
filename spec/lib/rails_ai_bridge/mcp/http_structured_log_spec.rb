# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::HttpStructuredLog do
  let(:request) do
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/mcp",
        "REMOTE_ADDR" => "203.0.113.1",
        "action_dispatch.request_id" => "abc-123"
      )
    )
  end

  around do |example|
    saved = RailsAiBridge.configuration.mcp.http_log_json
    example.run
  ensure
    RailsAiBridge.configuration.mcp.http_log_json = saved
  end

  describe ".emit" do
    it "does not call the logger when http_log_json is false" do
      RailsAiBridge.configuration.mcp.http_log_json = false
      expect(Rails.logger).not_to receive(:info)

      described_class.emit(request: request, event: :handled, http_status: 200)
    end

    it "logs one JSON line with msg, event, status, path, client_ip, and request_id when enabled" do
      RailsAiBridge.configuration.mcp.http_log_json = true
      expect(Rails.logger).to receive(:info) do |line|
        h = JSON.parse(line)
        expect(h["msg"]).to eq("rails_ai_bridge.mcp.http")
        expect(h["event"]).to eq("handled")
        expect(h["http_status"]).to eq(200)
        expect(h["path"]).to eq("/mcp")
        expect(h["client_ip"]).to eq("203.0.113.1")
        expect(h["request_id"]).to eq("abc-123")
      end

      described_class.emit(request: request, event: :handled, http_status: 200)
    end

    it "merges extra keyword fields and omits nil values" do
      RailsAiBridge.configuration.mcp.http_log_json = true
      expect(Rails.logger).to receive(:info) do |line|
        h = JSON.parse(line)
        expect(h["event"]).to eq("handled")
        expect(h["http_status"]).to eq(201)
        expect(h["mcp_session"]).to eq("abc")
        expect(h).not_to have_key("skipped")
      end

      described_class.emit(
        request: request,
        event: :handled,
        http_status: 201,
        mcp_session: "abc",
        skipped: nil
      )
    end
  end
end
