# frozen_string_literal: true

require "spec_helper"

module WatcherSpecListenStub
  # Listen substitute with a real `.to` method so RSpec partial doubles stay valid without the listen gem.
  def self.minimal_module
    m = Module.new
    m.define_singleton_method(:to) do |*_dirs, &_block|
      raise NotImplementedError, "stub with allow(Listen).to receive(:to)"
    end
    m
  end
end

RSpec.describe RailsAiBridge::Watcher do
  let(:tmpdir) { Dir.mktmpdir }
  let(:app) { instance_double("Rails::Application", root: Pathname.new(tmpdir)) }
  let(:watcher) { described_class.new(app) }

  after { FileUtils.remove_entry(tmpdir) }

  describe "WATCH_PATTERNS" do
    it "matches WatchDirectories defaults" do
      expect(described_class::WATCH_PATTERNS).to eq(RailsAiBridge::Watcher::WatchDirectories::DEFAULT_PATTERNS)
    end
  end

  describe "#start" do
    let(:listener) { double("Listen::Listener", start: nil, stop: nil) }

    context "when no watch directories exist" do
      before do
        stub_const("Listen", WatcherSpecListenStub.minimal_module)
        allow_any_instance_of(described_class).to receive(:require).and_call_original
        allow_any_instance_of(described_class).to receive(:require).with("listen").and_return(true)
      end

      it "returns early without calling Listen.to" do
        empty = Dir.mktmpdir
        begin
          empty_app = instance_double("Rails::Application", root: Pathname.new(empty))
          w = described_class.new(empty_app)
          expect(Listen).not_to receive(:to)
          expect { w.start }.to output(/No watchable directories found/).to_stderr
        ensure
          FileUtils.remove_entry(empty)
        end
      end
    end

    context "when watch directories exist" do
      before do
        FileUtils.mkdir_p(File.join(tmpdir, "app", "models"))
        stub_const("Listen", WatcherSpecListenStub.minimal_module)
        allow(Listen).to receive(:to).and_return(listener)
        allow_any_instance_of(described_class).to receive(:require).and_call_original
        allow_any_instance_of(described_class).to receive(:require).with("listen").and_return(true)
        allow_any_instance_of(described_class).to receive(:sleep).and_raise(Interrupt)
      end

      it "starts Listen on resolved roots and stops the listener on Interrupt" do
        expect(Listen).to receive(:to) do |*dirs, **_kwargs, &_block|
          expect(dirs).to include(File.join(tmpdir, "app", "models"))
          listener
        end

        expect(listener).to receive(:start)
        expect(listener).to receive(:stop)

        expect { watcher.start }.to output(/Watching for changes/).to_stderr
      end

      it "invokes regeneration when Listen reports filesystem changes" do
        regenerator = instance_spy(RailsAiBridge::Watcher::BridgeRegenerator)
        allow(RailsAiBridge::Watcher::BridgeRegenerator).to receive(:new).with(app).and_return(regenerator)
        allow(regenerator).to receive(:change_pending?).and_return(true)
        allow(regenerator).to receive(:regenerate!).and_return({ written: %w[/a], skipped: [] })

        allow(Listen).to receive(:to) do |*_dirs, &block|
          block&.call([ "x" ], [], [])
          listener
        end

        described_class.new(app).start

        expect(regenerator).to have_received(:change_pending?).at_least(:once)
        expect(regenerator).to have_received(:regenerate!)
      end
    end

    it "raises SystemExit with status 1 when the listen gem is not available" do
      stub_const("Listen", WatcherSpecListenStub.minimal_module)
      allow(Listen).to receive(:to).and_return(listener)
      allow(watcher).to receive(:sleep).and_raise(Interrupt)
      allow(watcher).to receive(:require).and_call_original
      allow(watcher).to receive(:require).with("listen").and_raise(LoadError)
      allow($stderr).to receive(:puts)

      expect do
        watcher.start
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
