# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Watcher::BridgeRegenerator do
  let(:tmpdir) { Dir.mktmpdir }
  let(:app) { instance_double(Rails::Application, root: Pathname.new(tmpdir)) }

  after { FileUtils.remove_entry(tmpdir) }

  describe '#initialize' do
    it 'stores the initial fingerprint from Fingerprinter' do
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(app).and_return('initial-digest')

      regenerator = described_class.new(app)

      expect(regenerator.last_fingerprint).to eq('initial-digest')
    end
  end

  describe '#change_pending?' do
    it 'delegates to Fingerprinter.changed?' do
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(app).and_return('fp')
      allow(RailsAiBridge::Fingerprinter).to receive(:changed?).with(app, 'fp').and_return(true)

      regenerator = described_class.new(app)

      expect(regenerator.change_pending?).to be true
    end
  end

  describe '#regenerate!' do
    it 'refreshes the fingerprint and returns generate_context output' do
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(app).and_return('old', 'new')
      allow(RailsAiBridge).to receive(:generate_context).with(app, format: :all, split_rules: true).and_return( # watcher_formats defaults to :all
        { written: %w[/tmp/a], skipped: %w[/tmp/b] }
      )

      regenerator = described_class.new(app)
      result = regenerator.regenerate!

      expect(result).to eq({ written: %w[/tmp/a], skipped: %w[/tmp/b] })
      expect(regenerator.last_fingerprint).to eq('new')
      expect(RailsAiBridge).to have_received(:generate_context).once
    end
  end
end
