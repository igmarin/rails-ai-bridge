# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Doctor::Checkers::BridgeFreshnessChecker do
  let(:tmpdir) { Dir.mktmpdir }
  let(:app) { instance_double(Rails::Application, root: Pathname.new(tmpdir)) }
  let(:checker) { described_class.new(app) }
  let(:output_dir) { tmpdir }

  before do
    allow(RailsAiBridge.configuration).to receive(:output_dir_for).with(app).and_return(output_dir)
    # Stub source fingerprint
    allow(RailsAiBridge::Fingerprinter).to receive(:source_fingerprint).with(app).and_return('a1b2c3d4e5f6')
  end

  after { FileUtils.remove_entry(tmpdir) }

  describe '#call' do
    context 'when no bridge files exist on disk' do
      it 'reports a warn check directing to run rails ai:bridge' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to eq('No bridge files found on disk')
        expect(result.fix).to include('rails ai:bridge')
      end
    end

    context 'when all existing bridge files are fresh' do
      before do
        # Generate CLAUDE.md with a fresh header
        content = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        File.write(File.join(output_dir, 'CLAUDE.md'), content)
      end

      it 'reports a pass check' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('All generated bridge files are fresh')
      end
    end

    context 'when some bridge files are missing but existing ones are fresh' do
      before do
        content = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        File.write(File.join(output_dir, 'CLAUDE.md'), content)
        # .cursorrules is missing
      end

      it 'reports a pass check (does not treat missing files as stale when some exist)' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('All generated bridge files are fresh')
      end
    end

    context 'when one or more bridge files are stale' do
      before do
        # Fresh CLAUDE.md
        fresh_content = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        File.write(File.join(output_dir, 'CLAUDE.md'), fresh_content)

        # Stale .cursorrules (different fingerprint)
        stale_content = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: oldfingerprt -->\n# Rules"
        File.write(File.join(output_dir, '.cursorrules'), stale_content)
      end

      it 'reports a warn check listing the stale files' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('Stale bridge files')
        expect(result.message).to include('.cursorrules')
        expect(result.message).not_to include('CLAUDE.md')
        expect(result.fix).to include('rails ai:bridge')
      end
    end

    context 'when JSON file exists' do
      context 'and it is fresh' do
        before do
          json_content = {
            '_meta' => {
              'source_fingerprint' => 'a1b2c3d4e5f6',
              'generated_at' => '2026-04-03T14:22:00Z'
            },
            'app_name' => 'Test'
          }.to_json
          File.write(File.join(output_dir, '.ai-context.json'), json_content)
        end

        it 'reports a pass check' do
          result = checker.call
          expect(result.status).to eq(:pass)
        end
      end

      context 'and it is stale' do
        before do
          json_content = {
            '_meta' => {
              'source_fingerprint' => 'oldfingerprt',
              'generated_at' => '2026-04-03T14:22:00Z'
            },
            'app_name' => 'Test'
          }.to_json
          File.write(File.join(output_dir, '.ai-context.json'), json_content)
        end

        it 'reports a warn check listing .ai-context.json' do
          result = checker.call
          expect(result.status).to eq(:warn)
          expect(result.message).to include('.ai-context.json')
        end
      end
    end

    context 'when a file read error occurs' do
      before do
        # Write CLAUDE.md first
        File.write(File.join(output_dir, 'CLAUDE.md'), 'some content')
        # Stub File.read to raise an error for CLAUDE.md
        allow(File).to receive(:read).with(File.join(output_dir, 'CLAUDE.md')).and_raise(Errno::EACCES)
      end

      it 'treats the file as stale and reports a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('CLAUDE.md')
      end
    end
  end
end
