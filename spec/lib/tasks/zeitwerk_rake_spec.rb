# frozen_string_literal: true

require 'open3'
require 'rake'
require 'spec_helper'

RSpec.describe 'rake zeitwerk:check' do
  it 'eager-loads the gem without errors' do
    command = ['bundle', 'exec', 'rake', 'zeitwerk:check']
    stdout, stderr, status = Open3.capture3(*command)

    aggregate_failures do
      expect(status).to be_success, "expected zeitwerk:check to pass, got exit #{status.exitstatus}\nstderr: #{stderr}\nstdout: #{stdout}"
      expect(stdout).to include('Zeitwerk check passed')
    end
  end
end

RSpec.describe 'zeitwerk:check loader selection' do
  let(:task_path) { File.expand_path('../../../lib/tasks/zeitwerk.rake', __dir__) }
  let!(:original_rake_application) { Rake.application }
  let(:gem_lib) { File.expand_path('../../../lib', __dir__) }

  before do
    Rake.application = Rake::Application.new
    load task_path
  end

  after do
    Rake.application = original_rake_application
  end

  it 'eager-loads only the loader whose dirs include the gem lib' do
    gem_loader = instance_double(Zeitwerk::Loader, dirs: [gem_lib], eager_load: nil)
    other_loader = instance_double(Zeitwerk::Loader, dirs: ['/some/host/lib'], eager_load: nil)

    allow(Zeitwerk::Registry.loaders).to receive(:each).and_yield(other_loader).and_yield(gem_loader)

    task = Rake::Task['zeitwerk:check']
    expect { task.execute }.to output(/Zeitwerk check passed\n/).to_stdout
    expect(gem_loader).to have_received(:eager_load)
    expect(other_loader).not_to have_received(:eager_load)
  end

  it 'raises a clear error when the gem loader is not found' do
    other_loader = instance_double(Zeitwerk::Loader, dirs: ['/some/host/lib'], eager_load: nil)

    allow(Zeitwerk::Registry.loaders).to receive(:each).and_yield(other_loader)

    task = Rake::Task['zeitwerk:check']
    expect { task.execute }.to raise_error(/RailsAiBridge Zeitwerk loader not found/)
    expect(other_loader).not_to have_received(:eager_load)
  end
end
