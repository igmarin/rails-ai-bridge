# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::RakeTaskIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    it "returns tasks array" do
      expect(result[:tasks]).to be_an(Array)
      expect(result[:tasks]).not_to be_empty
    end

    # From example.rake
    it "discovers namespaced tasks" do
      task_names = result[:tasks].map { |t| t[:name] }
      expect(task_names).to include("example:run", "example:setup")
    end

    it "extracts task descriptions" do
      run_task = result[:tasks].find { |t| t[:name] == "example:run" }
      expect(run_task[:description]).to eq("Run the example task")
    end

    it "extracts file path relative to lib/tasks" do
      run_task = result[:tasks].find { |t| t[:name] == "example:run" }
      expect(run_task[:file]).to eq("example.rake")
    end

    # From complex.rake
    it "discovers deeply nested namespace tasks" do
      task_names = result[:tasks].map { |t| t[:name] }
      expect(task_names).to include("deploy:db:migrate")
    end

    it "extracts descriptions from deeply nested tasks" do
      migrate = result[:tasks].find { |t| t[:name] == "deploy:db:migrate" }
      expect(migrate[:description]).to eq("Migrate staging database")
    end

    it "handles tasks without descriptions" do
      seed = result[:tasks].find { |t| t[:name] == "deploy:db:seed" }
      expect(seed).not_to be_nil
      expect(seed[:description]).to be_nil
    end

    it "discovers top-level tasks (no namespace)" do
      task_names = result[:tasks].map { |t| t[:name] }
      expect(task_names).to include("ping")
    end

    it "assigns correct namespace to all tasks" do
      deploy_staging = result[:tasks].find { |t| t[:name] == "deploy:staging" }
      expect(deploy_staging[:description]).to eq("Deploy to staging")
    end

    context "when lib/tasks does not exist" do
      let(:fake_app) { double(root: Pathname.new("/nonexistent")) }
      let(:introspector) { described_class.new(fake_app) }

      it "returns empty tasks array" do
        expect(result[:tasks]).to eq([])
      end
    end
  end
end
