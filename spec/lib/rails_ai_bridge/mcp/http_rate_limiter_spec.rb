# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Mcp::HttpRateLimiter do
  describe "#allow?" do
    it "allows requests under the limit" do
      limiter = described_class.new(max_requests: 3, window_seconds: 60)

      expect(limiter.allow?("1.2.3.4")).to be true
      expect(limiter.allow?("1.2.3.4")).to be true
      expect(limiter.allow?("1.2.3.4")).to be true
    end

    it "denies when the limit is reached within the window" do
      limiter = described_class.new(max_requests: 2, window_seconds: 60)

      expect(limiter.allow?("1.2.3.4")).to be true
      expect(limiter.allow?("1.2.3.4")).to be true
      expect(limiter.allow?("1.2.3.4")).to be false
    end

    it "tracks keys independently per IP" do
      limiter = described_class.new(max_requests: 1, window_seconds: 60)

      expect(limiter.allow?("10.0.0.1")).to be true
      expect(limiter.allow?("10.0.0.2")).to be true
    end

    it "resets the window after time advances" do
      tick = [ 1_000.0 ]
      clock = -> { tick.first }
      limiter = described_class.new(max_requests: 1, window_seconds: 10, clock: clock)

      expect(limiter.allow?("1.2.3.4")).to be true
      expect(limiter.allow?("1.2.3.4")).to be false

      tick[0] = 1_020.0

      expect(limiter.allow?("1.2.3.4")).to be true
    end

    it "uses unknown bucket for blank IP" do
      limiter = described_class.new(max_requests: 1, window_seconds: 60)

      expect(limiter.allow?("")).to be true
      expect(limiter.allow?(nil)).to be false
    end

    it "drops the per-client hash entry when all hits fall outside the window" do
      tick = [ 100.0 ]
      clock = -> { tick.first }
      limiter = described_class.new(max_requests: 5, window_seconds: 10, clock: clock)

      limiter.allow?("192.0.2.1")
      expect(limiter.instance_variable_get(:@hits)).to have_key("192.0.2.1")

      tick[0] = 200.0
      limiter.allow?("192.0.2.1")

      hits = limiter.instance_variable_get(:@hits)
      expect(hits["192.0.2.1"]).to eq([ 200.0 ])
    end
  end
end
