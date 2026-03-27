# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rails_ai_bridge rake tasks" do
  let(:rake) { Rake.application }
  let(:task_path) { File.expand_path("../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake", __dir__) }
  let(:result) { { written: [], skipped: [] } }
  let(:original_context_mode) { RailsAiBridge.configuration.context_mode }

  before(:context) do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake", __dir__)
  end

  after(:context) do
    Rake.application = @original_rake_application
  end

  before do
    rake.tasks.each(&:reenable)
    allow(RailsAiBridge).to receive(:generate_context).and_return(result)
  end

  after do
    RailsAiBridge.configuration.context_mode = original_context_mode
    ENV.delete("CONTEXT_MODE")
    ENV.delete("FORMAT")
  end

  def invoke_task(name, *args)
    rake[name].invoke(*args)
  end

  it "invokes ai:bridge with install selection (install.yml or default)" do
    invoke_task("ai:bridge")

    expect(RailsAiBridge).to have_received(:generate_context).with(format: :install)
  end

  it "invokes ai:bridge:all with every format" do
    invoke_task("ai:bridge:all")

    expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
  end

  it "invokes ai:bridge_for with the requested format" do
    invoke_task("ai:bridge_for", "cursor")

    expect(RailsAiBridge).to have_received(:generate_context).with(format: :cursor)
  end

  it "falls back to FORMAT for ai:bridge_for" do
    ENV["FORMAT"] = "copilot"

    invoke_task("ai:bridge_for")

    expect(RailsAiBridge).to have_received(:generate_context).with(format: :copilot)
  end

  it "invokes ai:bridge:claude with the claude format" do
    invoke_task("ai:bridge:claude")

    expect(RailsAiBridge).to have_received(:generate_context).with(format: :claude)
  end

  it "forces full mode for ai:bridge:full" do
    invoke_task("ai:bridge:full")

    expect(RailsAiBridge.configuration.context_mode).to eq(:full)
    expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
  end

  it "applies CONTEXT_MODE when generating a single format" do
    ENV["CONTEXT_MODE"] = "full"

    invoke_task("ai:bridge:json")

    expect(RailsAiBridge.configuration.context_mode).to eq(:full)
    expect(RailsAiBridge).to have_received(:generate_context).with(format: :json)
  end

  it "does not expose the legacy ai:context task" do
    expect(rake.lookup("ai:context")).to be_nil
  end
end
