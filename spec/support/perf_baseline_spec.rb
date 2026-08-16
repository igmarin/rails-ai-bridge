# frozen_string_literal: true

require 'spec_helper'
require_relative 'perf_baseline'

RSpec.describe PerfBaseline do
  describe '.benchmark_average' do
    it 'discards the first warmup sample and returns the median of the rest' do
      durations = [1.0, 0.02, 0.03, 0.025, 0.10, 0.028]
      clocks = durations.flat_map { |duration| [0.0, duration] }
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(*clocks)

      expect(described_class.benchmark_average { nil }).to eq(0.028)
    end
  end
end
