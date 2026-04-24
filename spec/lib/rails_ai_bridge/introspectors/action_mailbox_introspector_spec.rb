# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ActionMailboxIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns installed as false when ActionMailbox is not loaded' do
      expect(result[:installed]).to be false
    end

    it 'returns empty mailboxes array when no mailboxes directory' do
      expect(result[:mailboxes]).to eq([])
    end

    context 'with a mailbox file' do
      let(:mailboxes_dir) { Rails.root.join('app/mailboxes').to_s }
      let(:mailbox_file) { File.join(mailboxes_dir, 'forwards_mailbox.rb') }

      before do
        FileUtils.mkdir_p(mailboxes_dir)
        File.write(mailbox_file, <<~RUBY)
          class ForwardsMailbox < ApplicationMailbox
            routing /forwards/i => :forward

            def process
              # handle forwarded email
            end
          end
        RUBY
      end

      after { FileUtils.rm_rf(mailboxes_dir) }

      it 'discovers mailbox classes' do
        expect(result[:mailboxes].size).to eq(1)
        expect(result[:mailboxes].first[:name]).to eq('ForwardsMailbox')
      end

      it 'extracts routing patterns' do
        routing = result[:mailboxes].first[:routing]
        expect(routing).to be_an(Array)
      end
    end
  end
end
