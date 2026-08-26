# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::AppScope do
  let(:fake_app) { instance_double(Rails::Application) }
  let(:other_app) { instance_double(Rails::Application) }

  after do
    described_class.clear_app
  end

  describe '.current_app' do
    it 'defaults to Rails.application when no scope is set' do
      expect(described_class.current_app).to eq(Rails.application)
    end

    it 'returns the scoped app when inside with_app' do
      described_class.with_app(fake_app) do
        expect(described_class.current_app).to eq(fake_app)
      end
    end

    it 'returns Rails.application after the scope exits' do
      described_class.with_app(fake_app) do
        expect(described_class.current_app).to eq(fake_app)
      end
      expect(described_class.current_app).to eq(Rails.application)
    end

    it 'returns nil when no scope is set and Rails is not loaded' do
      described_class.clear_app
      hide_const('Rails')

      expect(described_class.current_app).to be_nil
    end
  end

  describe '.with_app' do
    it 'returns the block result' do
      result = described_class.with_app(fake_app) { :value }
      expect(result).to eq(:value)
    end

    it 'restores the prior app when the block raises' do
      described_class.with_app(fake_app) do
        raise StandardError, 'boom'
      rescue StandardError
        # swallow
      end

      expect(described_class.current_app).to eq(Rails.application)
    end

    it 'supports nested scopes that restore the prior app' do
      described_class.with_app(fake_app) do
        expect(described_class.current_app).to eq(fake_app)

        described_class.with_app(other_app) do
          expect(described_class.current_app).to eq(other_app)
        end

        expect(described_class.current_app).to eq(fake_app)
      end

      expect(described_class.current_app).to eq(Rails.application)
    end

    it 'restores the outer scope when the inner block raises' do
      described_class.with_app(fake_app) do
        described_class.with_app(other_app) do
          raise StandardError, 'inner boom'
        rescue StandardError
          # swallow
        end

        expect(described_class.current_app).to eq(fake_app)
      end
    end
  end

  describe 'concurrent isolation' do
    it 'does not leak app across threads' do
      described_class.with_app(fake_app) do
        Thread.new do
          expect(described_class.current_app).to eq(Rails.application)
        end.join
      end
    end

    it 'each thread can scope independently' do
      results = []
      mutex = Mutex.new
      ready = Queue.new
      start_signal = Queue.new

      threads = [fake_app, other_app].map do |app|
        Thread.new do
          ready << true
          start_signal.pop # wait for signal to proceed
          described_class.with_app(app) do
            mutex.synchronize { results << described_class.current_app }
          end
        end
      end

      2.times { ready.pop } # wait for both threads to be ready
      2.times { start_signal << true } # signal both to proceed
      threads.each(&:join)
      expect(results).to contain_exactly(fake_app, other_app)
    end
  end
end
