# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'quality rake tasks' do
  let(:task_path) { File.expand_path('../../../../lib/tasks/quality.rake', __dir__) }
  let(:original_rake_application) { Rake.application }

  before do
    Rake.application = Rake::Application.new
    load task_path
  end

  after do
    Rake.application = original_rake_application
  end

  it 'defines a YARD documentation gate' do
    expect(Rake::Task.task_defined?('docs:yard')).to be(true)
  end

  it 'defines a Reek quality gate' do
    expect(Rake::Task.task_defined?('quality:reek')).to be(true)
  end
end
