# frozen_string_literal: true

require 'json'

# Performance regression baseline comparison for rails-ai-bridge.
#
# Generates a JSON baseline of key metrics (introspection time, context
# generation time, MCP tool response time) and compares each CI run against
# the committed baseline in +spec/support/perf_baseline.json+.
#
# A regression exceeding 20% over the baseline fails the perf job.
# Each metric is the median of five timed iterations after one discarded warmup.
module PerfBaseline
  BASELINE_PATH = File.expand_path('perf_baseline.json', __dir__)
  REGRESSION_THRESHOLD = 0.20
  WARMUP_ITERATIONS = 1
  MEASURED_ITERATIONS = 5

  # Measures the three key perf metrics against the combustion dummy app.
  #
  # @return [Hash{Symbol => Float}] measured metrics in seconds
  def self.measure
    require 'rails_ai_bridge'

    {
      introspection_time_sec: measure_introspection,
      context_generation_time_sec: measure_context_generation,
      mcp_tool_response_time_sec: measure_mcp_tool_response
    }
  end

  # Loads the committed baseline JSON.
  #
  # @return [Hash] baseline data with +metrics+ key
  def self.load_baseline
    JSON.parse(File.read(BASELINE_PATH))
  end

  # Compares measured metrics against the baseline, returning a report hash.
  #
  # @param measured [Hash{Symbol => Float}] measured metrics
  # @return [Hash] report with per-metric delta, percent change, and +regressed+ flag
  def self.compare(measured)
    baseline = load_baseline.fetch('metrics')
    threshold = REGRESSION_THRESHOLD

    results = measured.to_h do |name, value|
      base = baseline.fetch(name.to_s).to_f
      delta = value - base
      percent = base.zero? ? 0.0 : (delta / base)
      [
        name,
        {
          baseline: base,
          measured: value,
          delta: delta,
          percent_change: percent,
          regressed: percent > threshold
        }
      ]
    end

    {
      metrics: results,
      threshold: threshold,
      regressed: results.values.any? { |r| r[:regressed] }
    }
  end

  # Runs the full measure + compare cycle, printing a human-readable report.
  # Exits with status 1 when any metric regresses beyond the threshold.
  #
  # @return [void]
  def self.run
    measured = measure
    report = compare(measured)

    puts 'Performance baseline comparison:'
    puts "  Threshold: #{(REGRESSION_THRESHOLD * 100).to_i}% regression"
    puts
    report.fetch(:metrics).each do |name, data|
      status = data[:regressed] ? 'REGRESSION' : 'OK'
      percent = format('%<sign>.1f%%', sign: data[:percent_change] * 100)
      puts format('  %<name>-35s baseline=%<baseline>.4fs measured=%<measured>.4fs delta=%<delta>s [%<status>s]',
                  name: name, baseline: data[:baseline], measured: data[:measured],
                  delta: percent, status: status)
    end

    if report.fetch(:regressed)
      puts
      puts 'Performance regression detected — exceeding 20% threshold.'
      exit 1
    end

    puts
    puts 'All metrics within baseline threshold.'
  end

  # Generates a fresh baseline JSON from a measurement run and writes it to disk.
  #
  # @return [void]
  def self.generate
    measured = measure
    existing = File.exist?(BASELINE_PATH) ? load_baseline : {}
    data = existing.merge(
      'version' => 1,
      'metrics' => measured.transform_keys(&:to_s)
    )
    File.write(BASELINE_PATH, "#{JSON.pretty_generate(data)}\n")
    puts "Baseline written to #{BASELINE_PATH}"
    measured.each do |name, value|
      puts format('  %<name>-35s %<value>.4fs', name: name, value: value)
    end
  end

  # @api private
  def self.measure_introspection
    app = Rails.application
    introspector = RailsAiBridge::Introspector.new(app)
    benchmark_average do
      introspector.call(only: %i[schema routes])
    end
  end

  # @api private
  def self.measure_context_generation
    context = RailsAiBridge::Introspector.new(Rails.application).call(only: %i[schema routes])
    benchmark_average do
      RailsAiBridge::Serializers::Providers::CodexSerializer.new(context).call
    end
  end

  # @api private
  def self.measure_mcp_tool_response
    benchmark_average do
      RailsAiBridge::Tools::GetSchema.call(detail: 'summary')
    end
  end

  # @api private
  def self.benchmark_average
    samples = Array.new(WARMUP_ITERATIONS + MEASURED_ITERATIONS) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
    median(samples.drop(WARMUP_ITERATIONS)).round(4)
  end

  # @api private
  def self.median(samples)
    sorted = samples.sort
    mid = sorted.length / 2
    return sorted[mid] if sorted.length.odd?

    (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
