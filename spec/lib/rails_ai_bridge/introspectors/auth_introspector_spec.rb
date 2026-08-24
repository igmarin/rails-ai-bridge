# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::AuthIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns authentication as a hash' do
      expect(result[:authentication]).to be_a(Hash)
    end

    it 'returns authorization as a hash' do
      expect(result[:authorization]).to be_a(Hash)
    end

    it 'returns security as a hash' do
      expect(result[:security]).to be_a(Hash)
    end

    it 'returns empty auth when no auth framework present' do
      expect(result[:authentication][:devise]).to be_nil
      expect(result[:authentication][:rails_auth]).to be_nil
    end

    it 'returns empty authorization when no policies' do
      expect(result[:authorization][:pundit]).to be_nil
      expect(result[:authorization][:cancancan]).to be_nil
    end

    context 'with has_secure_password in a model' do
      let(:fixture_model) { Rails.root.join('app/models/account.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Account < ApplicationRecord
            has_secure_password
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects has_secure_password with model name' do
        expect(result[:authentication][:has_secure_password]).to include('Account')
      end
    end

    context 'with Devise in a model' do
      let(:fixture_model) { Rails.root.join('app/models/admin.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Admin < ApplicationRecord
            devise :database_authenticatable, :registerable, :recoverable
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects Devise models with modules' do
        devise_entry = result[:authentication][:devise]&.find { |d| d[:model] == 'Admin' }
        expect(devise_entry).not_to be_nil
        expect(devise_entry[:matches].first).to include('database_authenticatable')
      end
    end

    context 'with Pundit policies' do
      let(:policies_dir) { Rails.root.join('app/policies').to_s }

      before do
        FileUtils.mkdir_p(policies_dir)
        File.write(File.join(policies_dir, 'post_policy.rb'), 'class PostPolicy; end')
      end

      after { FileUtils.rm_rf(policies_dir) }

      it 'detects Pundit policies' do
        expect(result[:authorization][:pundit]).to include('PostPolicy')
      end
    end

    context 'with CSP initializer' do
      let(:csp_file) { Rails.root.join('config/initializers/content_security_policy.rb').to_s }

      before do
        FileUtils.mkdir_p(File.dirname(csp_file))
        File.write(csp_file, '# CSP config')
      end

      after { FileUtils.rm_f(csp_file) }

      it 'detects CSP' do
        expect(result[:security][:csp]).to be true
      end
    end

    context 'with configured auth paths' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('rails-ai-bridge-auth')) }
      let(:models_dir) { app_root.join('domain/models') }
      let(:policies_dir) { app_root.join('authorization/policies') }
      let(:custom_app) do
        double(
          'Rails::Application',
          root: app_root,
          paths: {
            'app/models' => [models_dir.to_s],
            'app/policies' => [policies_dir.to_s]
          }
        )
      end

      after { FileUtils.rm_rf(app_root) }

      before do
        FileUtils.mkdir_p(models_dir)
        FileUtils.mkdir_p(policies_dir)
        FileUtils.mkdir_p(app_root.join('app/controllers/concerns'))
        File.write(models_dir.join('current.rb'), 'class Current < ActiveSupport::CurrentAttributes; end')
        File.write(models_dir.join('session.rb'), 'class Session < ApplicationRecord; end')
        File.write(models_dir.join('user.rb'), <<~RUBY)
          class User < ApplicationRecord
            devise :database_authenticatable
            has_secure_password
            generates_token_for :password_reset
            normalizes :email
          end
        RUBY
        File.write(app_root.join('app/controllers/concerns/authentication.rb'), 'module Authentication; end')
        File.write(models_dir.join('ability.rb'), 'class Ability; end')
        File.write(policies_dir.join('order_policy.rb'), 'class OrderPolicy; end')
      end

      it 'detects authentication and authorization outside conventional app paths' do
        custom_result = described_class.new(custom_app).call

        expect(custom_result[:authentication][:rails_auth]).to include(
          authentication_concern: true,
          token_for: [{ model: 'User', tokens: ['password_reset'] }],
          normalized_attributes: [{ model: 'User', attrs: ['email'] }]
        )
        expect(custom_result[:authentication][:has_secure_password]).to include('User')
        expect(custom_result[:authentication][:devise].first[:model]).to eq('User')
        expect(custom_result[:authorization]).to include(
          pundit: ['OrderPolicy'],
          cancancan: true
        )
      end
    end

    context 'with rack-cors gem and cors initializer' do
      let(:lockfile) { Rails.root.join('Gemfile.lock').to_s }
      let(:cors_init) { Rails.root.join('config/initializers/cors.rb').to_s }
      let!(:original_lockfile) { File.exist?(lockfile) ? File.read(lockfile) : nil }
      let!(:original_cors) { File.exist?(cors_init) ? File.read(cors_init) : nil }

      before do
        File.write(lockfile, "    rack-cors (2.0.0)\n")
        FileUtils.mkdir_p(File.dirname(cors_init))
        File.write(cors_init, '# CORS config')
      end

      after do
        if original_lockfile
          File.write(lockfile, original_lockfile)
        else
          FileUtils.rm_f(lockfile)
        end
        if original_cors
          File.write(cors_init, original_cors)
        else
          FileUtils.rm_f(cors_init)
        end
      end

      it 'detects CORS as configured' do
        expect(result[:security][:cors]).to eq({ configured: true })
      end
    end

    context 'with rack-cors gem but no cors initializer' do
      let(:lockfile) { Rails.root.join('Gemfile.lock').to_s }
      let!(:original_content) { File.exist?(lockfile) ? File.read(lockfile) : nil }

      before do
        File.write(lockfile, "    rack-cors (2.0.0)\n")
      end

      after do
        if original_content
          File.write(lockfile, original_content)
        else
          FileUtils.rm_f(lockfile)
        end
      end

      it 'detects CORS as not configured' do
        expect(result[:security][:cors]).to eq({ configured: false })
      end
    end

    context 'when detect_authentication raises' do
      before { allow(introspector).to receive(:detect_authentication).and_raise(StandardError, 'auth boom') }

      it 'returns error hash' do
        expect(result[:error]).to eq('auth boom')
      end
    end
  end

  describe 'private methods' do
    describe '#gem_present?' do
      it 'returns false when Gemfile.lock does not exist' do
        allow(introspector).to receive(:root).and_return('/nonexistent')
        expect(introspector.send(:gem_present?, 'rack-cors')).to be false
      end

      it 'returns false on file read error' do
        lockfile = Rails.root.join('Gemfile.lock').to_s
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(lockfile).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(lockfile).and_raise(StandardError, 'read error')
        expect(introspector.send(:gem_present?, 'rack-cors')).to be false
      ensure
        allow(File).to receive(:read).and_call_original
      end
    end

    describe '#scan_models_for error handling' do
      it 'returns empty array on error' do
        allow(introspector.path_resolver).to receive(:files_for).and_raise(StandardError, 'files error')
        expect(introspector.send(:scan_models_for, /devise/)).to eq([])
      end
    end

    describe '#policy_names error handling' do
      it 'returns empty array on error' do
        allow(introspector.path_resolver).to receive(:files_for).and_raise(StandardError, 'policies error')
        expect(introspector.send(:policy_names)).to eq([])
      end
    end
  end
end
