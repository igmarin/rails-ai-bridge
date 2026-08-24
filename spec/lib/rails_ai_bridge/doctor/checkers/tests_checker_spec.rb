# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Doctor::Checkers::TestsChecker do
  let(:tmpdir) { Dir.mktmpdir }
  let(:app) { instance_double(Rails::Application, root: Pathname.new(tmpdir)) }
  let(:checker) { described_class.new(app) }

  after { FileUtils.remove_entry(tmpdir) }

  describe '#call' do
    context 'when a spec directory exists' do
      before { FileUtils.mkdir_p(File.join(tmpdir, 'spec')) }

      it 'reports a pass with the RSpec framework name' do
        result = checker.call

        expect(result.status).to eq(:pass)
        expect(result.message).to include('RSpec')
      end
    end

    context 'when only a test directory exists' do
      before { FileUtils.mkdir_p(File.join(tmpdir, 'test')) }

      it 'reports a pass with the Minitest framework name' do
        result = checker.call

        expect(result.status).to eq(:pass)
        expect(result.message).to include('Minitest')
      end
    end

    context 'when neither spec nor test directory exists' do
      it 'reports a warn check' do
        result = checker.call

        expect(result.status).to eq(:warn)
        expect(result.message).to include('No test directory found')
        expect(result.fix).to include('rspec:install')
      end
    end
  end
end
