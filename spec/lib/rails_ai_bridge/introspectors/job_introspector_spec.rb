# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::JobIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    before do
      stub_const('ActiveJob::Base', Class.new)
      stub_const('ActionMailer::Base', Class.new)
      stub_const('ActionCable::Channel::Base', Class.new)
    end

    it 'returns jobs array' do
      expect(result[:jobs]).to be_an(Array)
    end

    it 'returns mailers array' do
      expect(result[:mailers]).to be_an(Array)
    end

    it 'returns channels array' do
      expect(result[:channels]).to be_an(Array)
    end

    context 'when classes have subclasses' do
      before do
        job_class = Class.new(ActiveJob::Base) do
          def self.name
            'MyJob'
          end

          def self.queue_name
            'default'
          end

          def self.priority
            1
          end
        end

        proc_job_class = Class.new(ActiveJob::Base) do
          def self.name
            'ProcJob'
          end

          def self.queue_name
            -> { 'dynamic_queue' }
          end

          def self.priority
            2
          end
        end

        error_proc_job_class = Class.new(ActiveJob::Base) do
          def self.name
            'ErrorProcJob'
          end

          def self.queue_name
            -> { raise StandardError }
          end

          def self.priority
            nil
          end
        end

        allow(ActiveJob::Base).to receive(:descendants).and_return([job_class, proc_job_class, error_proc_job_class])

        mailer_class = Class.new(ActionMailer::Base) do
          def self.name
            'MyMailer'
          end

          def self.delivery_method
            :smtp
          end

          def test_action; end
        end
        allow(ActionMailer::Base).to receive(:descendants).and_return([mailer_class])

        channel_class = Class.new(ActionCable::Channel::Base) do
          def self.name
            'MyChannel'
          end

          def stream_for_user; end
          def subscribed; end
        end
        allow(ActionCable::Channel::Base).to receive(:descendants).and_return([channel_class])
      end

      it 'extracts job metadata including proc queues' do
        expect(result[:jobs]).to include(
          { name: 'MyJob', queue: 'default', priority: 1 },
          { name: 'ProcJob', queue: 'dynamic_queue', priority: 2 },
          a_hash_including(name: 'ErrorProcJob')
        )
      end

      it 'extracts mailer metadata' do
        expect(result[:mailers]).to include({ name: 'MyMailer', actions: ['test_action'], delivery_method: 'smtp' })
      end

      it 'extracts channel metadata' do
        expect(result[:channels]).to include(
          hash_including(
            name: 'MyChannel',
            stream_methods: contain_exactly('stream_for_user', 'subscribed')
          )
        )
      end
    end

    context 'when rescuing errors' do
      before do
        allow(ActiveJob::Base).to receive(:descendants).and_raise(StandardError)
        allow(ActionMailer::Base).to receive(:descendants).and_raise(StandardError)
        allow(ActionCable::Channel::Base).to receive(:descendants).and_raise(StandardError)
      end

      it 'returns empty arrays gracefully' do
        expect(result).to eq({ jobs: [], mailers: [], channels: [] })
      end
    end
  end
end
