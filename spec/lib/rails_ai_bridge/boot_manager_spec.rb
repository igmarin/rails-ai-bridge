# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::BootManager do
  let(:root_path) { Dir.mktmpdir('boot-manager-test-') }

  after { FileUtils.rm_rf(root_path) }

  describe '.locate_root' do
    it 'finds root from a directory containing a Gemfile' do
      File.write(File.join(root_path, 'Gemfile'), "source 'https://rubygems.org'")
      expect(described_class.locate_root(root_path)).to eq(Pathname.new(root_path))
    end

    it 'finds root from a directory containing config/application.rb' do
      FileUtils.mkdir_p(File.join(root_path, 'config'))
      File.write(File.join(root_path, 'config/application.rb'), 'module TestApp; end')
      expect(described_class.locate_root(root_path)).to eq(Pathname.new(root_path))
    end

    it 'returns nil when no Rails app markers are found' do
      expect(described_class.locate_root(root_path)).to be_nil
    end

    it 'walks up the tree to find a parent with a Gemfile' do
      File.write(File.join(root_path, 'Gemfile'), "source 'https://rubygems.org'")
      subdir = File.join(root_path, 'app', 'models')
      FileUtils.mkdir_p(subdir)
      expect(described_class.locate_root(subdir)).to eq(Pathname.new(root_path))
    end
  end

  describe '.boot' do
    let(:bootable_root) do
      parent = Dir.mktmpdir
      path = File.join(parent, 'boot_fixture')
      FileUtils.mkdir_p(File.join(path, 'config'))
      File.write(File.join(path, 'Gemfile'), "source 'https://rubygems.org'")
      File.write(File.join(path, 'config/application.rb'), <<~RUBY)
        module BootFixture
          class Application
            def self.initialize!; end
          end
        end
      RUBY
      path
    end

    after do
      parent = File.dirname(bootable_root)
      FileUtils.rm_rf(parent)
    end

    it 'returns a structured result with success: true when boot succeeds' do
      # Pre-load the fixture so constantize can find it
      load File.join(bootable_root, 'config', 'application.rb')
      allow(described_class).to receive(:require).and_return(true)

      result = described_class.boot(bootable_root, timeout: 5)

      expect(result[:success]).to be(true)
      expect(result[:app]).to eq(BootFixture::Application)
    end

    it 'returns a structured result with success: false when boot fails' do
      result = described_class.boot(Pathname.new(root_path), timeout: 5)

      expect(result[:success]).to be(false)
      expect(result).to have_key(:error)
      expect(result[:error]).to be_a(String)
    end

    it 'includes the error class in the failure result' do
      result = described_class.boot(Pathname.new(root_path), timeout: 5)

      expect(result).to have_key(:error_class)
    end

    it 'quarantines boot stdout to stderr (does not pollute stdout)' do
      result = described_class.boot(Pathname.new(root_path), timeout: 5)

      expect(result).to have_key(:stdout_quarantined)
      expect(result[:stdout_quarantined]).to be(true)
    end
  end

  describe '.boot with timeout' do
    it 'honors a configurable timeout' do
      # A non-bootable path with a very short timeout should fail quickly
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = described_class.boot(Pathname.new(root_path), timeout: 1)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(result[:success]).to be(false)
      expect(elapsed).to be < 5
    end
  end

  describe '.static_fallback' do
    it 'returns a StaticApp for the given root' do
      app = described_class.static_fallback(root_path)

      expect(app).to be_a(RailsAiBridge::StaticApp)
      expect(app.root).to eq(Pathname.new(root_path))
    end
  end

  describe '.offer_static_fallback?' do
    it 'returns true for commands that permit static fallback' do
      expect(described_class.offer_static_fallback?(:context)).to be(true)
      expect(described_class.offer_static_fallback?(:inspect)).to be(true)
      expect(described_class.offer_static_fallback?(:doctor)).to be(true)
    end

    it 'returns false for commands that require boot' do
      expect(described_class.offer_static_fallback?(:serve)).to be(false)
      expect(described_class.offer_static_fallback?(:watch)).to be(false)
    end
  end
end
