# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::DevOpsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns nil for puma when no config exists' do
      expect(result[:puma]).to be_nil
    end

    it 'returns empty procfile array when no Procfile exists' do
      expect(result[:procfile]).to eq([])
    end

    it 'returns nil for deployment when no deploy config exists' do
      expect(result[:deployment]).to be_nil
    end

    it 'returns nil for docker when no Dockerfile exists' do
      expect(result[:docker]).to be_nil
    end

    context 'with a Puma config' do
      let(:puma_config) { Rails.root.join('config/puma.rb').to_s }

      before do
        File.write(puma_config, <<~RUBY)
          threads 5, 10
          workers 2
          port ENV.fetch("PORT", 3000)
        RUBY
      end

      after { FileUtils.rm_f(puma_config) }

      it 'extracts Puma threads' do
        expect(result[:puma][:threads_min]).to eq(5)
        expect(result[:puma][:threads_max]).to eq(10)
      end

      it 'extracts Puma workers' do
        expect(result[:puma][:workers]).to eq(2)
      end

      it 'extracts Puma port' do
        expect(result[:puma][:port]).to eq(3000)
      end
    end

    context 'with a Procfile' do
      let(:procfile) { Rails.root.join('Procfile').to_s }

      before do
        File.write(procfile, <<~PROCFILE)
          web: bundle exec puma -C config/puma.rb
          worker: bundle exec sidekiq
        PROCFILE
      end

      after { FileUtils.rm_f(procfile) }

      it 'parses Procfile entries' do
        entries = result[:procfile].flat_map { |p| p[:entries] }
        names = entries.pluck(:name)
        expect(names).to include('web', 'worker')
      end
    end

    context 'with a Dockerfile' do
      let(:dockerfile) { Rails.root.join('Dockerfile').to_s }

      before do
        File.write(dockerfile, <<~DOCKER)
          FROM ruby:3.3-slim AS base
          FROM base AS build
          RUN bundle install
        DOCKER
      end

      after { FileUtils.rm_f(dockerfile) }

      it 'detects multi-stage Docker build' do
        expect(result[:docker][:multi_stage]).to be true
        expect(result[:docker][:base_images]).to include('ruby:3.3-slim AS base')
      end
    end

    context 'with health check route' do
      let(:routes_file) { Rails.root.join('config/routes.rb').to_s }
      let(:original_routes) { File.read(routes_file) }

      before do
        File.write(routes_file, "#{original_routes}\n# get \"up\" => \"rails/health#show\"\n")
      end

      after { File.write(routes_file, original_routes) }

      it 'detects health check with word boundary' do
        expect(result[:health_check]).to be true
      end
    end
  end

  describe '#call with custom app root' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('devops')) }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:introspector) { described_class.new(custom_app) }
    let(:result) { introspector.call }

    after { FileUtils.rm_rf(app_root) }

    context 'with kamal deploy config' do
      before { FileUtils.mkdir_p(app_root.join('config')); File.write(app_root.join('config/deploy.yml'), 'service: app') }

      it 'detects kamal as deployment tool' do
        expect(result[:deployment]).to eq('kamal')
      end
    end

    context 'with Capfile' do
      before { File.write(app_root.join('Capfile'), "require 'capistrano/setup'") }

      it 'detects capistrano as deployment tool' do
        expect(result[:deployment]).to eq('capistrano')
      end
    end

    context 'with app.json (heroku)' do
      before { File.write(app_root.join('app.json'), '{"name": "app"}') }

      it 'detects heroku as deployment tool' do
        expect(result[:deployment]).to eq('heroku')
      end
    end

    context 'with Procfile (heroku)' do
      before { File.write(app_root.join('Procfile'), 'web: bundle exec puma') }

      it 'detects heroku as deployment tool from Procfile' do
        expect(result[:deployment]).to eq('heroku')
      end
    end

    context 'with Procfile.dev' do
      before { File.write(app_root.join('Procfile.dev'), "web: puma\njs: yarn build") }

      it 'parses Procfile.dev entries' do
        files = result[:procfile].map { |p| p[:file] }
        expect(files).to include('Procfile.dev')
      end
    end

    context 'with Procfile with comments and empty lines' do
      before do
        File.write(app_root.join('Procfile'), <<~PROCFILE)
          # This is a comment

          web: bundle exec puma
        PROCFILE
      end

      it 'skips comments and empty lines' do
        entries = result[:procfile].flat_map { |p| p[:entries] }
        expect(entries.size).to eq(1)
        expect(entries.first[:name]).to eq('web')
      end
    end

    context 'with Procfile with malformed line' do
      before { File.write(app_root.join('Procfile'), 'just-a-line-without-colon') }

      it 'skips lines without colon' do
        entries = result[:procfile].flat_map { |p| p[:entries] }
        expect(entries).to eq([])
      end
    end

    context 'with empty Procfile' do
      before { File.write(app_root.join('Procfile'), '') }

      it 'returns empty procfile array' do
        expect(result[:procfile]).to eq([])
      end
    end

    context 'with puma.rb but no recognizable config' do
      before do
        FileUtils.mkdir_p(app_root.join('config'))
        File.write(app_root.join('config/puma.rb'), '# just a comment')
      end

      it 'returns nil for puma when no config extracted' do
        expect(result[:puma]).to be_nil
      end
    end

    context 'with Dockerfile with single FROM' do
      before do
        File.write(app_root.join('Dockerfile'), 'FROM ruby:3.3-slim')
        File.write(app_root.join('docker-compose.yml'), 'version: 3')
      end

      it 'detects single-stage build and compose file' do
        expect(result[:docker][:multi_stage]).to be false
        expect(result[:docker][:compose]).to be true
      end
    end

    context 'with no routes.rb' do
      it 'returns nil for health_check' do
        expect(result[:health_check]).to be_nil
      end
    end

    context 'with routes.rb without health check' do
      before do
        FileUtils.mkdir_p(app_root.join('config'))
        File.write(app_root.join('config/routes.rb'), 'Rails.application.routes.draw { resources :posts }')
      end

      it 'returns nil for health_check when no health route' do
        expect(result[:health_check]).to be_nil
      end
    end
  end

  describe '#call when app.root raises' do
    let(:bad_app) { double('Rails::Application') }
    let(:result) { described_class.new(bad_app).call }

    before { allow(bad_app).to receive(:root).and_raise(StandardError, 'root boom') }

    it 'returns error hash' do
      expect(result[:error]).to eq('root boom')
    end
  end
end
