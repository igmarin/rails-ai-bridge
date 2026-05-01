# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ConventionDetector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'returns architecture as an array' do
      expect(result[:architecture]).to be_an(Array)
    end

    it 'returns patterns as an array' do
      expect(result[:patterns]).to be_an(Array)
    end

    it 'returns directory_structure as a hash' do
      expect(result[:directory_structure]).to be_a(Hash)
    end

    it 'detects models directory' do
      expect(result[:directory_structure]).to have_key('app/models')
    end

    it 'returns config_files as an array' do
      expect(result[:config_files]).to be_an(Array)
    end

    it 'does not advertise Rails credentials or key files as config files' do
      allow(introspector).to receive(:file_exists?).and_return(true)

      expect(result[:config_files]).not_to include('config/credentials.yml.enc')
      expect(result[:config_files]).not_to include('config/master.key')
    end

    context 'with custom Rails directory paths' do
      let(:tmpdir) { Dir.mktmpdir('rails-ai-bridge-conventions') }
      let(:service_dir) { File.join(tmpdir, 'domain', 'services') }
      let(:models_dir) { File.join(tmpdir, 'domain', 'models') }
      let(:custom_app) do
        instance_double(
          Rails::Application,
          root: Pathname.new(tmpdir),
          config: instance_double(Rails::Application::Configuration, api_only: false),
          paths: {
            'app/services' => [service_dir],
            'app/models' => [models_dir]
          }
        )
      end
      let(:introspector) { described_class.new(custom_app) }

      before do
        FileUtils.mkdir_p(service_dir)
        FileUtils.mkdir_p(models_dir)
        File.write(File.join(service_dir, 'sync_customer.rb'), "class SyncCustomer\nend\n")
        File.write(File.join(models_dir, 'secure_profile.rb'), "class SecureProfile\n  encrypts :ssn\nend\n")
      end

      after { FileUtils.remove_entry(tmpdir) }

      it 'detects architecture from configured Rails paths without exposing absolute paths' do
        expect(result[:architecture]).to include('service_objects')
        expect(result[:patterns]).to include('encrypted_attributes')
        expect(result[:directory_structure]).to include('app/services' => 1, 'app/models' => 1)
        expect(result[:directory_structure].keys.join).not_to include(tmpdir)
      end
    end
  end
end
