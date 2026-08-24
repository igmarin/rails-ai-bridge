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

    it 'returns an error hash when convention detection fails' do
      allow(introspector).to receive(:detect_architecture).and_raise(StandardError, 'convention failure')

      expect(introspector.call).to eq(error: 'convention failure')
    end

    it 'does not advertise Rails credentials or key files as config files' do
      allow(introspector).to receive(:file_exists?).and_return(true)

      expect(result[:config_files]).not_to include('config/credentials.yml.enc')
      expect(result[:config_files]).not_to include('config/master.key')
    end
  end

  describe '#call with custom app root' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('conventions')) }
    let(:custom_app) do
      double('Rails::Application', root: app_root,
                                   config: double('Config', api_only: true),
                                   paths: {})
    end
    let(:introspector) { described_class.new(custom_app) }
    let(:result) { introspector.call }

    after { FileUtils.rm_rf(app_root) }

    it 'detects api_only architecture' do
      expect(result[:architecture]).to include('api_only')
    end

    context 'with various architecture directories' do
      before do
        FileUtils.mkdir_p(app_root.join('app/graphql'))
        FileUtils.mkdir_p(app_root.join('app/api'))
        FileUtils.mkdir_p(app_root.join('app/forms'))
        FileUtils.mkdir_p(app_root.join('app/queries'))
        FileUtils.mkdir_p(app_root.join('app/presenters'))
        FileUtils.mkdir_p(app_root.join('app/components'))
        FileUtils.mkdir_p(app_root.join('app/models/concerns'))
        FileUtils.mkdir_p(app_root.join('app/controllers/concerns'))
        FileUtils.mkdir_p(app_root.join('app/validators'))
        FileUtils.mkdir_p(app_root.join('app/policies'))
        FileUtils.mkdir_p(app_root.join('app/serializers'))
        FileUtils.mkdir_p(app_root.join('app/notifiers'))
        FileUtils.mkdir_p(app_root.join('app/javascript/controllers'))
        FileUtils.mkdir_p(app_root.join('app/decorators'))
        FileUtils.mkdir_p(app_root.join('.github/workflows'))
        FileUtils.mkdir_p(app_root.join('app/views/pwa'))
        FileUtils.mkdir_p(app_root.join('config'))
        File.write(app_root.join('config/importmap.rb'), 'pin "application"')
        File.write(app_root.join('Dockerfile'), 'FROM ruby:3.3')
        File.write(app_root.join('config/deploy.yml'), 'service: app')
      end

      it 'detects all architecture features' do
        arch = result[:architecture]
        expect(arch).to include('graphql', 'grape_api', 'form_objects', 'query_objects',
                                'presenters', 'view_components', 'hotwire', 'stimulus',
                                'importmaps', 'concerns_models', 'concerns_controllers',
                                'validators', 'policies', 'serializers', 'notifiers',
                                'pwa', 'docker', 'kamal', 'ci_github_actions')
      end
    end

    context 'with model patterns' do
      before do
        FileUtils.mkdir_p(app_root.join('app/models'))
        File.write(app_root.join('app/models/user.rb'), <<~RUBY)
          class User < ApplicationRecord
            has_many :posts, polymorphic: true
            acts_as_paranoid
            has_paper_trail
            aasm column: :status
            acts_as_tenant :account
            searchkick
            acts_as_taggable_on :tags
            friendly_id :slug
            acts_as_nested_set
            encrypts :ssn
            normalizes :email
          end
        RUBY
      end

      it 'detects all source patterns' do
        patterns = result[:patterns]
        expect(patterns).to include('polymorphic', 'soft_delete', 'versioning',
                                    'state_machine', 'multi_tenancy', 'searchable',
                                    'taggable', 'sluggable', 'nested_set',
                                    'encrypted_attributes', 'normalizations')
      end
    end

    context 'with unreadable model file' do
      before do
        FileUtils.mkdir_p(app_root.join('app/models'))
        path = app_root.join('app/models/bad.rb').to_s
        File.write(path, 'class Bad; end')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(path).and_raise(StandardError, 'read error')
      end

      after { allow(File).to receive(:read).and_call_original }

      it 'handles file read errors gracefully in detect_patterns' do
        expect(result[:patterns]).to be_an(Array)
      end
    end

    context 'with no Gemfile.lock' do
      it 'returns false for gem_present?' do
        expect(introspector.send(:gem_present?, 'turbo-rails')).to be false
      end
    end

    context 'with Gemfile.lock containing turbo-rails' do
      before { File.write(app_root.join('Gemfile.lock'), "    turbo-rails (2.0.0)\n") }

      it 'detects gem presence' do
        expect(introspector.send(:gem_present?, 'turbo-rails')).to be true
      end
    end
  end

  describe '.log_error' do
    it 'logs warning and handles missing Rails.logger' do
      error = StandardError.new('test error')
      expect { described_class.log_error(error) }.not_to raise_error
    end
  end

  describe '#call with custom Rails directory paths' do
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
    let(:result) { introspector.call }

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
