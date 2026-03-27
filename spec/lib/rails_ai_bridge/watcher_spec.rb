# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Watcher do
  describe "#initialize" do
    it "defaults app to Rails.application" do
      watcher = described_class.new
      expect(watcher.app).to eq(Rails.application)
    end

    it "accepts an explicit app" do
      fake = instance_double(Rails::Application)
      allow(fake).to receive(:root).and_return(Pathname.new("/tmp"))
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(fake).and_return("fp1")

      watcher = described_class.new(fake)
      expect(watcher.app).to eq(fake)
    end
  end

  describe "#start" do
    context "when no watchable directories exist" do
      it "prints a message and returns without calling Listen" do
        require "listen" # defines +Listen+ for the expectation below

        root = Pathname.new(Dir.mktmpdir)
        fake_app = instance_double(Rails::Application, root: root)
        allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(fake_app).and_return("fp")

        watcher = described_class.new(fake_app)
        expect(Listen).not_to receive(:to)

        expect { watcher.start }.to output(/No watchable directories/).to_stderr
      end
    end

    context "when watchable directories exist" do
      it "starts Listen, runs one wait iteration, then stops on Interrupt from sleep" do
        require "listen"

        listener = instance_double(Listen::Listener)
        allow(listener).to receive(:start)
        allow(listener).to receive(:stop)
        allow(Listen).to receive(:to).and_return(listener)

        watcher = described_class.new(Rails.application)
        # +loop+ inside +#start+ resolves on the watcher instance; shadow Kernel’s infinite +loop+ for one iteration.
        watcher.define_singleton_method(:loop) do |&block|
          block.call
        end
        allow(watcher).to receive(:sleep).with(1).and_raise(Interrupt.new)

        expect(listener).to receive(:start)
        expect(listener).to receive(:stop)
        expect { watcher.start }.to output(/Watching for changes/).to_stderr
      end
    end
  end

  describe "#handle_change" do
    it "does nothing when fingerprint is unchanged" do
      watcher = described_class.new(Rails.application)
      allow(RailsAiBridge::Fingerprinter).to receive(:changed?).and_return(false)

      expect(RailsAiBridge).not_to receive(:generate_context)
      watcher.send(:handle_change)
    end

    it "regenerates context when fingerprint changed" do
      watcher = described_class.new(Rails.application)
      allow(RailsAiBridge::Fingerprinter).to receive(:changed?).and_return(true)
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).and_return("new_fp")
      allow(RailsAiBridge).to receive(:generate_context).with(format: :install).and_return({ written: %w[/a.md], skipped: [] })

      expect do
        watcher.send(:handle_change)
      end.to output(%r{Updated: /a\.md}).to_stderr
    end

    it "rescues and logs errors from generate_context" do
      watcher = described_class.new(Rails.application)
      allow(RailsAiBridge::Fingerprinter).to receive(:changed?).and_return(true)
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).and_return("fp")
      allow(RailsAiBridge).to receive(:generate_context).and_raise(StandardError.new("boom"))

      expect do
        watcher.send(:handle_change)
      end.to output(/Error regenerating: boom/).to_stderr
    end
  end
end
