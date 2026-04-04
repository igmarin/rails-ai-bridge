# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::ProviderDocumentHeader do
  let(:ctx) do
    {
      app_name: "MyApp",
      rails_version: "7.2.0",
      ruby_version: "3.3.0",
      generated_at: "2024-06-01T12:00:00Z"
    }
  end

  describe ".call" do
    it "raises on unknown layout" do
      expect do
        described_class.call(context: ctx, document_title: "X", intro: "Hi", layout: :bogus)
      end.to raise_error(ArgumentError, /unknown header layout/)
    end

    it "matches HeaderFormatter output for the default AI context intro" do
      intro = <<~INTRO.chomp
        This file gives AI assistants (Claude Code, Cursor, Copilot) deep context
        about this Rails application's structure, patterns, and conventions.
      INTRO
      from_helper = described_class.call(context: ctx, document_title: "AI Context", layout: :ai_context, intro: intro)
      from_formatter = RailsAiBridge::Serializers::Formatters::Providers::HeaderFormatter.new(ctx).call
      expect(from_helper).to eq(from_formatter)
    end
  end

  describe ".rules_banner" do
    it "matches RulesHeaderFormatter output" do
      from_helper = described_class.rules_banner(context: ctx)
      from_formatter = RailsAiBridge::Serializers::Formatters::Providers::RulesHeaderFormatter.new(ctx).call
      expect(from_helper).to eq(from_formatter)
    end
  end
end
