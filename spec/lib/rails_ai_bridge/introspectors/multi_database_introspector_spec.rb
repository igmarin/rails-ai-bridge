# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::MultiDatabaseIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "returns databases array" do
      expect(result[:databases]).to be_an(Array)
    end

    it "returns multi_db flag" do
      expect(result[:multi_db]).to be(true).or be(false)
    end

    it "returns replicas array" do
      expect(result[:replicas]).to be_an(Array)
    end

    it "returns model_connections array" do
      expect(result[:model_connections]).to be_an(Array)
    end

    it "does not return an error" do
      expect(result[:error]).to be_nil
    end
  end

  describe "model connection detection" do
    before do
      @models_dir = File.join(app.root.to_s, "app/models")
      FileUtils.mkdir_p(@models_dir)

      File.write(File.join(@models_dir, "animals_record.rb"), <<~RUBY)
        class AnimalsRecord < ApplicationRecord
          self.abstract_class = true
          connects_to database: { writing: :animals, reading: :animals_replica }
        end
      RUBY
    end

    after do
      FileUtils.rm_f(File.join(@models_dir, "animals_record.rb"))
    end

    it "detects connects_to in models" do
      result = introspector.call
      connections = result[:model_connections]
      animal = connections.find { |c| c[:model] == "AnimalsRecord" }
      expect(animal).not_to be_nil
      expect(animal[:connects_to]).to include("animals")
    end
  end
end
