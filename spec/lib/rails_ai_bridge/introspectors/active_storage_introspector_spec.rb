# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ActiveStorageIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    context 'with attachment macros in model source' do
      let(:fixture_model) { Rails.root.join('app/models/profile.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Profile < ApplicationRecord
            has_one_attached :avatar
            has_many_attached :documents
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects has_one_attached' do
        avatars = result[:attachments].select { |a| a[:name] == 'avatar' }
        expect(avatars.size).to eq(1)
        expect(avatars.first[:type]).to eq('has_one_attached')
        expect(avatars.first[:model]).to eq('Profile')
      end

      it 'detects has_many_attached' do
        docs = result[:attachments].select { |a| a[:name] == 'documents' }
        expect(docs.size).to eq(1)
        expect(docs.first[:type]).to eq('has_many_attached')
      end
    end

    it 'extracts storage services from config' do
      expect(result[:storage_services]).to include('local')
      expect(result[:storage_services]).to include('test')
    end

    it 'returns false for direct_upload when none present' do
      expect(result[:direct_upload]).to be false
    end

    it 'treats direct upload scan path errors as no direct uploads' do
      resolver = instance_double(
        RailsAiBridge::PathResolver,
        files_for: [],
        glob_for: nil
      )
      allow(resolver).to receive(:glob_for).and_raise(StandardError, 'path failure')
      allow(RailsAiBridge::PathResolver).to receive(:new).and_return(resolver)

      expect(described_class.new(Rails.application).call[:direct_upload]).to be false
    end

    it 'returns installed flag as boolean' do
      expect(result[:installed]).to be(true).or be(false)
    end

    context 'with configured Rails paths' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('rails-ai-bridge-active-storage')) }
      let(:models_dir) { app_root.join('domain/models') }
      let(:views_dir) { app_root.join('frontend/templates') }
      let(:custom_app) do
        double(
          'Rails::Application',
          root: app_root,
          paths: {
            'app/models' => [models_dir.to_s],
            'app/views' => [views_dir.to_s],
            'app/javascript' => [app_root.join('frontend/javascript').to_s]
          }
        )
      end

      after { FileUtils.rm_rf(app_root) }

      before do
        FileUtils.mkdir_p(models_dir)
        FileUtils.mkdir_p(views_dir)
        File.write(models_dir.join('asset_profile.rb'), <<~RUBY)
          class AssetProfile < ApplicationRecord
            has_one_attached :avatar
          end
        RUBY
        File.write(views_dir.join('profiles.html.erb'), '<%= form.file_field :avatar, direct_upload: true %>')
      end

      it 'detects attachments and direct uploads outside conventional app directories' do
        custom_result = described_class.new(custom_app).call

        expect(custom_result[:attachments]).to include(
          model: 'AssetProfile',
          name: 'avatar',
          type: 'has_one_attached'
        )
        expect(custom_result[:direct_upload]).to be true
      end
    end
  end
end
