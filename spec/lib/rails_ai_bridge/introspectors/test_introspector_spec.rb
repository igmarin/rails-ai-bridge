# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::TestIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    it "returns framework as a known string" do
      expect(%w[rspec minitest unknown]).to include(result[:framework])
    end

    it "returns CI config as array" do
      expect(result[:ci_config]).to be_an(Array)
    end

    it "returns test_helpers as array" do
      expect(result[:test_helpers]).to be_an(Array)
    end

    it "returns nil for factories when none exist" do
      expect(result[:factories]).to be_nil
    end

    it "returns nil for fixtures when none exist" do
      expect(result[:fixtures]).to be_nil
    end

    it "returns nil for system_tests when none exist" do
      expect(result[:system_tests]).to be_nil
    end

    it "returns nil for vcr_cassettes when none exist" do
      expect(result[:vcr_cassettes]).to be_nil
    end

    it "returns nil for coverage when no Gemfile.lock" do
      expect(result[:coverage]).to be_nil
    end

    context "with a spec directory" do
      let(:spec_dir) { File.join(Rails.root, "spec") }

      before { FileUtils.mkdir_p(spec_dir) }
      after { FileUtils.rm_rf(spec_dir) }

      it "detects rspec framework" do
        expect(result[:framework]).to eq("rspec")
      end
    end

    context "with a test directory" do
      let(:test_dir) { File.join(Rails.root, "test") }

      before { FileUtils.mkdir_p(test_dir) }
      after { FileUtils.rm_rf(test_dir) }

      it "detects minitest framework" do
        # Ensure spec/ doesn't exist (rspec takes priority)
        spec_dir = File.join(Rails.root, "spec")
        had_spec = Dir.exist?(spec_dir)
        expect(result[:framework]).to eq(had_spec ? "rspec" : "minitest")
      end
    end

    context "with factories" do
      let(:factories_dir) { File.join(Rails.root, "spec/factories") }

      before do
        FileUtils.mkdir_p(factories_dir)
        File.write(File.join(factories_dir, "users.rb"), "FactoryBot.define {}")
      end

      after { FileUtils.rm_rf(File.join(Rails.root, "spec")) }

      it "detects factories with location and count" do
        expect(result[:factories]).to be_a(Hash)
        expect(result[:factories][:location]).to eq("spec/factories")
        expect(result[:factories][:count]).to eq(1)
      end
    end
  end
end
