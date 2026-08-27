# frozen_string_literal: true

require 'spec_helper'
require 'rake'
require_relative '../../../support/rake_spec_helpers'

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

  describe 'docs:yard' do
    def stub_yard_output(output, success)
      status = double('status', success?: success)
      allow(Open3).to receive(:capture2e).and_return([output, status])
    end

    it 'prints the YARD stats when the documented percent meets the minimum' do
      stub_yard_output("90.5% documented\n", true)

      expect { Rake::Task['docs:yard'].execute }.to output(/90\.5% documented/).to_stdout
    end

    it 'aborts when the command fails' do
      stub_yard_output('something went wrong', false)

      expect { Rake::Task['docs:yard'].execute }.to raise_error(SystemExit, /below 90\.0%/)
    end

    it 'aborts when the output has no documented percentage' do
      stub_yard_output('no stats available', true)

      expect { Rake::Task['docs:yard'].execute }.to raise_error(SystemExit, /below 90\.0%/)
    end

    it 'aborts when the documented percentage is below the minimum' do
      stub_yard_output("50.0% documented\n", true)

      expect { Rake::Task['docs:yard'].execute }.to raise_error(SystemExit, /below 90\.0%/)
    end

    it 'honors a custom YARD_MINIMUM_PERCENT' do
      stub_yard_output("60.0% documented\n", true)

      with_env('YARD_MINIMUM_PERCENT' => '50') do
        expect { Rake::Task['docs:yard'].execute }.to output(/60\.0% documented/).to_stdout
      end
    end
  end

  describe 'quality:reek' do
    it 'runs reek against lib/' do
      allow(rake_top_level).to receive(:sh).and_return(true)

      expect { Rake::Task['quality:reek'].execute }.not_to raise_error
      expect(rake_top_level).to have_received(:sh).with('reek', 'lib/')
    end
  end
end
