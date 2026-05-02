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
        File.write(models_dir.join('current.rb'), 'class Current < ActiveSupport::CurrentAttributes; end')
        File.write(models_dir.join('session.rb'), 'class Session < ApplicationRecord; end')
        File.write(models_dir.join('user.rb'), <<~RUBY)
          class User < ApplicationRecord
            devise :database_authenticatable
            has_secure_password
          end
        RUBY
        File.write(models_dir.join('ability.rb'), 'class Ability; end')
        File.write(policies_dir.join('order_policy.rb'), 'class OrderPolicy; end')
      end

      it 'detects authentication and authorization outside conventional app paths' do
        custom_result = described_class.new(custom_app).call

        expect(custom_result[:authentication][:rails_auth]).to be true
        expect(custom_result[:authentication][:has_secure_password]).to include('User')
        expect(custom_result[:authentication][:devise].first[:model]).to eq('User')
        expect(custom_result[:authorization]).to include(
          pundit: ['OrderPolicy'],
          cancancan: true
        )
      end
    end
  end
end
