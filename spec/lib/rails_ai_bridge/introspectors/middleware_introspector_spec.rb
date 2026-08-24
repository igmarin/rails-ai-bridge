# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::MiddlewareIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  let(:middleware_dir) { File.join(app.root.to_s, 'app/middleware') }

  before do
    FileUtils.mkdir_p(middleware_dir)

    File.write(File.join(middleware_dir, 'tenant_resolver.rb'), <<~RUBY)
      class TenantResolver
        def initialize(app)
          @app = app
        end

        def call(env)
          tenant = extract_tenant(env)
          Current.tenant = tenant
          @app.call(env)
        end

        private

        def extract_tenant(env)
          request = Rack::Request.new(env)
          subdomain = request.host.split(".").first
          Account.find_by(subdomain: subdomain)
        end
      end
    RUBY

    File.write(File.join(middleware_dir, 'request_logger.rb'), <<~RUBY)
      class RequestLogger
        def initialize(app)
          @app = app
        end

        def call(env)
          Rails.logger.info "Request: \#{env['REQUEST_METHOD']} \#{env['PATH_INFO']}"
          @app.call(env)
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(middleware_dir)
  end

  describe '#call' do
    subject(:result) { introspector.call }

    it 'discovers custom middleware files' do
      custom = result[:custom_middleware]
      expect(custom.size).to eq(2)
      names = custom.pluck(:class_name)
      expect(names).to include('TenantResolver', 'RequestLogger')
    end

    it 'detects middleware patterns' do
      tenant = result[:custom_middleware].find { |m| m[:class_name] == 'TenantResolver' }
      expect(tenant[:detected_patterns]).to include('tenant')
      expect(tenant[:has_call_method]).to be true
      expect(tenant[:initializes_app]).to be true
    end

    it 'detects logging pattern' do
      logger = result[:custom_middleware].find { |m| m[:class_name] == 'RequestLogger' }
      expect(logger[:detected_patterns]).to include('logging')
    end

    it 'extracts middleware stack' do
      expect(result[:middleware_stack]).to be_an(Array)
      expect(result[:middleware_stack]).not_to be_empty
    end

    it 'returns middleware count' do
      expect(result[:middleware_count][:custom]).to eq(2)
      expect(result[:middleware_count][:total]).to be > 0
    end

    it 'does not return an error' do
      expect(result[:error]).to be_nil
    end
  end

  describe '#call with no app/middleware directory' do
    let(:result) { introspector.call }

    before { FileUtils.rm_rf(middleware_dir) }

    it 'returns empty custom_middleware array' do
      expect(result[:custom_middleware]).to eq([])
    end
  end

  describe '#call with middleware patterns' do
    let(:result) { introspector.call }

    before do
      File.write(File.join(middleware_dir, 'auth_middleware.rb'), <<~RUBY)
        class AuthMiddleware
          def initialize(app)
            @app = app
          end

          def call(env)
            token = env['HTTP_AUTHORIZATION']
            @app.call(env)
          end
        end
      RUBY

      File.write(File.join(middleware_dir, 'cors_middleware.rb'), <<~RUBY)
        class CorsMiddleware
          def initialize(app)
            @app = app
          end

          def call(env)
            headers = { 'Access-Control-Allow-Origin' => '*' }
            @app.call(env)
          end
        end
      RUBY

      File.write(File.join(middleware_dir, 'rate_limiter.rb'), <<~RUBY)
        class RateLimiter
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
          end
        end
      RUBY

      File.write(File.join(middleware_dir, 'cache_middleware.rb'), <<~RUBY)
        class CacheMiddleware
          def initialize(app)
            @app = app
          end

          def call(env)
            etag = env['HTTP_IF_NONE_MATCH']
            @app.call(env)
          end
        end
      RUBY

      File.write(File.join(middleware_dir, 'error_handler.rb'), <<~RUBY)
        class ErrorHandler
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
          rescue StandardError => e
            [500, {}, ['error']]
          end
        end
      RUBY
    end

    it 'detects authentication pattern' do
      auth = result[:custom_middleware].find { |m| m[:class_name] == 'AuthMiddleware' }
      expect(auth[:detected_patterns]).to include('authentication')
    end

    it 'detects cors pattern' do
      cors = result[:custom_middleware].find { |m| m[:class_name] == 'CorsMiddleware' }
      expect(cors[:detected_patterns]).to include('cors')
    end

    it 'detects rate_limiting pattern' do
      rate = result[:custom_middleware].find { |m| m[:class_name] == 'RateLimiter' }
      expect(rate[:detected_patterns]).to include('rate_limiting')
    end

    it 'detects caching pattern' do
      cache = result[:custom_middleware].find { |m| m[:class_name] == 'CacheMiddleware' }
      expect(cache[:detected_patterns]).to include('caching')
    end

    it 'detects error_handling pattern' do
      err = result[:custom_middleware].find { |m| m[:class_name] == 'ErrorHandler' }
      expect(err[:detected_patterns]).to include('error_handling')
    end
  end

  describe '#call with unreadable middleware file' do
    let(:bad_file) { File.join(middleware_dir, 'bad_middleware.rb') }
    let(:result) { introspector.call }

    before do
      File.write(bad_file, 'class BadMiddleware; end')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(bad_file).and_raise(StandardError, 'read error')
    end

    after { allow(File).to receive(:read).and_call_original }

    it 'includes error entry for unreadable middleware' do
      bad = result[:custom_middleware].find { |m| m[:file] == 'app/middleware/bad_middleware.rb' }
      expect(bad[:error]).to eq('read error')
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
