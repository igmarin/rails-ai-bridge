# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::RulesSerializer do
  let(:context) do
    {
      app_name: 'MyApp',
      rails_version: '7.1.3',
      ruby_version: '3.3.0'
    }
  end
  let(:config) { RailsAiBridge::Configuration.new }
  let(:serializer) { described_class.new(context, config: config) }

  describe '#call' do
    context 'when context_mode is :compact (default)' do
      before do
        config.context_mode = :compact
      end

      it 'delegates to RulesOrchestrator' do
        orchestrator_double = instance_double(RailsAiBridge::Serializers::Providers::RulesOrchestrator)
        allow(RailsAiBridge::Serializers::Providers::RulesOrchestrator).to receive(:new)
          .with(context: context, config: config)
          .and_return(orchestrator_double)

        expect(orchestrator_double).to receive(:call).and_return('Compact Rules')

        expect(serializer.call).to eq('Compact Rules')
      end
    end

    context 'when context_mode is :full' do
      before do
        config.context_mode = :full
      end

      it 'delegates to MarkdownSerializer with rules formatters' do
        markdown_double = instance_double(RailsAiBridge::Serializers::MarkdownSerializer)
        
        allow(RailsAiBridge::Serializers::MarkdownSerializer).to receive(:new)
          .with(
            context,
            header_class: RailsAiBridge::Serializers::Formatters::Providers::RulesHeaderFormatter,
            footer_class: RailsAiBridge::Serializers::Formatters::Providers::RulesFooterFormatter
          )
          .and_return(markdown_double)

        expect(markdown_double).to receive(:call).and_return('Full Rules')

        expect(serializer.call).to eq('Full Rules')
      end
    end
  end
end
