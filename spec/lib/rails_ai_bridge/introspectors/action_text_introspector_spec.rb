# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::ActionTextIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    it "returns installed as false when ActionText is not loaded" do
      expect(result[:installed]).to be false
    end

    context "with rich text macros in model source" do
      let(:fixture_model) { File.join(Rails.root, "app/models/article.rb") }

      before do
        File.write(fixture_model, <<~RUBY)
          class Article < ApplicationRecord
            has_rich_text :content
            has_rich_text :summary
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it "detects all rich text fields" do
        fields = result[:rich_text_fields].select { |f| f[:model] == "Article" }
        expect(fields.size).to eq(2)
        expect(fields.map { |f| f[:field] }).to contain_exactly("content", "summary")
      end
    end

    context "without rich text macros" do
      it "returns empty rich_text_fields" do
        expect(result[:rich_text_fields]).to eq([])
      end
    end
  end
end
