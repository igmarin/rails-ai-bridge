# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ApiIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns api_only as false for standard app' do
      expect(result[:api_only]).to be false
    end

    it 'returns serializers as a hash' do
      expect(result[:serializers]).to be_a(Hash)
    end

    it 'returns api versioning array' do
      expect(result[:api_versioning]).to be_an(Array)
    end

    it 'returns rate limiting as empty hash when no rate limiting' do
      expect(result[:rate_limiting]).to be_a(Hash)
    end

    it 'detects v1 API versioning from directory structure' do
      expect(result[:api_versioning]).to include('v1')
    end

    it 'returns nil for graphql when no app/graphql dir' do
      expect(result[:graphql]).to be_nil
    end

    context 'with a serializer directory' do
      let(:serializers_dir) { Rails.root.join('app/serializers').to_s }
      let(:serializer_file) { File.join(serializers_dir, 'post_serializer.rb') }

      before do
        FileUtils.mkdir_p(serializers_dir)
        File.write(serializer_file, <<~RUBY)
          class PostSerializer
            def call(post)
              { id: post.id, title: post.title }
            end
          end
        RUBY
      end

      after { FileUtils.rm_rf(serializers_dir) }

      it 'detects serializer classes' do
        expect(result[:serializers][:serializer_classes]).to include('PostSerializer')
      end
    end

    context 'with rack-attack initializer' do
      let(:init_path) { Rails.root.join('config/initializers/rack_attack.rb').to_s }

      before do
        FileUtils.mkdir_p(File.dirname(init_path))
        File.write(init_path, '# Rack::Attack config')
      end

      after { FileUtils.rm_f(init_path) }

      it 'detects rack_attack rate limiting' do
        expect(result[:rate_limiting]).to eq({ rack_attack: true })
      end
    end

    context 'with configured API paths' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('rails-ai-bridge-api')) }
      let(:paths) do
        {
          'app/views' => [app_root.join('frontend/views').to_s],
          'app/serializers' => [app_root.join('presentation/serializers').to_s],
          'app/graphql' => [app_root.join('interface/graphql').to_s],
          'app/controllers' => [app_root.join('interface/controllers').to_s]
        }
      end
      let(:custom_app) do
        double(
          'Rails::Application',
          root: app_root,
          paths: paths,
          config: double('ApplicationConfig', api_only: true)
        )
      end

      after { FileUtils.rm_rf(app_root) }

      before do
        paths.values.flatten.each { |path| FileUtils.mkdir_p(path) }
        FileUtils.mkdir_p(app_root.join('interface/graphql/types'))
        FileUtils.mkdir_p(app_root.join('interface/graphql/mutations'))
        FileUtils.mkdir_p(app_root.join('interface/controllers/api/v2'))
        File.write(app_root.join('frontend/views/show.json.jbuilder'), 'json.id @record.id')
        File.write(app_root.join('presentation/serializers/order_serializer.rb'), 'class OrderSerializer; end')
        File.write(app_root.join('interface/graphql/types/order_type.rb'), 'class Types::OrderType; end')
        File.write(app_root.join('interface/graphql/mutations/create_order.rb'), 'class Mutations::CreateOrder; end')
        File.write(app_root.join('interface/controllers/api/v2/orders_controller.rb'), <<~RUBY)
          class Api::V2::OrdersController < ApplicationController
            rate_limit to: 10, within: 1.minute
          end
        RUBY
      end

      it 'detects serializers, GraphQL, API versions, and rate limits outside conventional app paths' do
        custom_result = described_class.new(custom_app).call

        expect(custom_result[:serializers]).to include(
          jbuilder: 1,
          serializer_classes: ['OrderSerializer']
        )
        expect(custom_result[:graphql]).to eq(types: 1, mutations: 1, queries: 0)
        expect(custom_result[:api_versioning]).to include('v2')
        expect(custom_result[:rate_limiting]).to eq(rails_rate_limiting: true)
      end
    end
  end
end
