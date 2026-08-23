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

      after { FileUtils.rm_f(mailbox_file) }

      it 'discovers mailbox classes' do
        expect(result[:mailboxes].size).to eq(1)
        expect(result[:mailboxes].first[:name]).to eq('ForwardsMailbox')
      end

      it 'extracts routing patterns' do
        routing = result[:mailboxes].first[:routing]
        expect(routing).to be_an(Array)
      end
    end

    context 'with application_mailbox.rb and a mailbox without routing' do
      let(:mailboxes_dir) { Rails.root.join('app/mailboxes').to_s }

      before do
        FileUtils.mkdir_p(mailboxes_dir)
        File.write(File.join(mailboxes_dir, 'application_mailbox.rb'), "class ApplicationMailbox < ActionMailbox::Base\nend\n")
        File.write(File.join(mailboxes_dir, 'bounces_mailbox.rb'), "class BouncesMailbox < ApplicationMailbox\n  def process\n  end\nend\n")
      end

      after do
        FileUtils.rm_f(File.join(mailboxes_dir, 'application_mailbox.rb'))
        FileUtils.rm_f(File.join(mailboxes_dir, 'bounces_mailbox.rb'))
      end

      it 'skips application_mailbox.rb' do
        names = result[:mailboxes].pluck(:name)
        expect(names).not_to include('ApplicationMailbox')
        expect(names).to include('BouncesMailbox')
      end

      it 'returns empty routing for mailbox without routing rules' do
        bounce = result[:mailboxes].find { |m| m[:name] == 'BouncesMailbox' }
        expect(bounce[:routing]).to eq([])
      end
    end

    context 'with an unreadable mailbox file' do
      let(:mailboxes_dir) { Rails.root.join('app/mailboxes').to_s }
      let(:bad_file) { File.join(mailboxes_dir, 'bad_mailbox.rb') }

      before do
        FileUtils.mkdir_p(mailboxes_dir)
        File.write(bad_file, 'class BadMailbox; end')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(bad_file).and_raise(StandardError, 'read error')
      end

      after do
        allow(File).to receive(:read).and_call_original
        FileUtils.rm_f(bad_file)
      end

      it 'skips unreadable mailbox files' do
        expect(result[:mailboxes]).to eq([])
      end
    end

    context 'when app.root raises' do
      let(:bad_app) { double('Rails::Application') }
      let(:result) { described_class.new(bad_app).call }

      before { allow(bad_app).to receive(:root).and_raise(StandardError, 'root boom') }

      it 'returns error hash' do
        expect(result[:error]).to eq('root boom')
      end
    end
  end
end
