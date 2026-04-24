# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::TurboIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'discovers turbo frames with id and file' do
      expect(result[:turbo_frames]).to be_an(Array)
      frame = result[:turbo_frames].find { |f| f[:id] == 'post' }
      expect(frame).not_to be_nil
      expect(frame[:file]).to eq('posts/show.html.erb')
    end

    it 'discovers turbo stream templates' do
      expect(result[:turbo_streams]).to include('posts/create.turbo_stream.erb')
    end

    it 'returns model_broadcasts as empty when no broadcasts in models' do
      expect(result[:model_broadcasts]).to eq([])
    end

    context 'with a model that uses broadcasts' do
      let(:fixture_model) { Rails.root.join('app/models/message.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Message < ApplicationRecord
            broadcasts_to :room
            broadcasts_refreshes_to :room
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects model broadcasts' do
        broadcast = result[:model_broadcasts].find { |b| b[:model] == 'Message' }
        expect(broadcast).not_to be_nil
        expect(broadcast[:methods]).to include('broadcasts_to', 'broadcasts_refreshes_to')
      end
    end
  end
end
