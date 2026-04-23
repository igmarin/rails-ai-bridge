# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'rails_ai_bridge rake tasks' do
  let(:rake) { Rake.application }
  let(:task_path) { File.expand_path('../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake', __dir__) }
  let(:result) { { written: [], skipped: [] } }
  let(:original_context_mode) { RailsAiBridge.configuration.context_mode }

  let(:original_rake_application) { Rake.application }

  before do
    # Setup new Rake application for each test to avoid state leakage
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path('../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake', __dir__)

    rake.tasks.each(&:reenable)
    allow(RailsAiBridge).to receive(:generate_context).and_return(result)
  end

  after do
    # Restore original Rake application
    Rake.application = original_rake_application
    RailsAiBridge.configuration.context_mode = original_context_mode
  end

  describe 'ai:bridge' do
    it 'calls generate_context with the :all format' do
      rake['ai:bridge'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
    end

    it 'prints written and skipped files' do
      result[:written] = ['/foo/CLAUDE.md']
      result[:skipped] = ['/foo/.cursorrules']

      expect { rake['ai:bridge'].invoke }.to output(%r{✅ /foo/CLAUDE\.md}).to_stdout
      expect { rake['ai:bridge'].invoke }.to output(%r{⏭️  /foo/\.cursorrules \(unchanged\)}).to_stdout
    end
  end

  describe 'ai:bridge_for' do
    it 'calls generate_context with the specified format' do
      rake['ai:bridge_for'].invoke('cursor')
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :cursor)
    end

    it 'calls generate_context with format from ENV' do
      ENV['FORMAT'] = 'codex'
      rake['ai:bridge_for'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :codex)
    end

    it 'defaults to claude when no format is specified' do
      ENV.delete('FORMAT') # Ensure no ENV variable is interfering
      rake['ai:bridge_for'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :claude)
    end
  end

  describe 'ai:bridge:full' do
    it 'sets context_mode to :full and calls generate_context with :all' do
      rake['ai:bridge:full'].invoke
      expect(RailsAiBridge.configuration.context_mode).to eq(:full)
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all)
    end
  end

  describe 'ai:serve' do
    it 'starts the MCP server with stdio transport' do
      allow(RailsAiBridge).to receive(:start_mcp_server).with(transport: :stdio)
      rake['ai:serve'].invoke
    end
  end

  describe 'ai:serve_http' do
    it 'starts the MCP server with http transport' do
      allow(RailsAiBridge).to receive(:start_mcp_server).with(transport: :http)
      rake['ai:serve_http'].invoke
    end
  end

  describe 'ai:inspect' do
    it 'prints introspection summary to stdout' do
      allow(RailsAiBridge).to receive(:introspect).and_return({
                                                                app_name: 'TestApp',
                                                                rails_version: '7.1.3',
                                                                ruby_version: '3.3.0',
                                                                schema: { adapter: 'postgresql', total_tables: 5 },
                                                                models: { 'User' => {}, 'Post' => {} },
                                                                routes: { total_routes: 10 },
                                                                jobs: { jobs: [], mailers: [] },
                                                                conventions: { architecture: ['Service Objects'] }
                                                              })

      expect { rake['ai:inspect'].invoke }.to output(/TestApp — AI Context Summary/).to_stdout
      expect { rake['ai:inspect'].invoke }.to output(/Rails 7\.1\.3 \| Ruby 3\.3\.0/).to_stdout
      expect { rake['ai:inspect'].invoke }.to output(/📦 Database: 5 tables \(postgresql\)/).to_stdout
      expect { rake['ai:inspect'].invoke }.to output(/🏗️  Models: 2/).to_stdout
      expect { rake['ai:inspect'].invoke }.to output(/🛤️  Routes: 10/).to_stdout
      expect { rake['ai:inspect'].invoke }.to output(/🏛️  Architecture: Service Objects/).to_stdout
    end

    it 'handles introspection errors gracefully' do
      allow(RailsAiBridge).to receive(:introspect).and_return({
                                                                app_name: 'TestApp',
                                                                rails_version: '7.1.3',
                                                                ruby_version: '3.3.0',
                                                                schema: { error: 'DB connection failed' }
                                                              })

      expect { rake['ai:inspect'].invoke }.to output(/TestApp — AI Context Summary/).to_stdout
      expect { rake['ai:inspect'].invoke }.not_to output(/📦 Database/).to_stdout
    end
  end

  describe 'ai:doctor' do
    it 'runs diagnostic checks' do
      doctor_result = { score: 100, checks: [double(name: 'Check1', message: 'OK', status: :pass, fix: nil)] }
      doctor_instance = double('Doctor', run: doctor_result)
      allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

      expect { rake['ai:doctor'].invoke }.to output(/🩺 Running AI readiness diagnostics\.\.\./).to_stdout
      expect { rake['ai:doctor'].invoke }.to output(/✅ Check1: OK/).to_stdout
      expect { rake['ai:doctor'].invoke }.to output(%r{AI Readiness Score: 100/100}).to_stdout
    end
  end

  # New test for gemini
  describe 'ai:bridge:gemini' do
    it 'calls generate_context with the :gemini format' do
      rake['ai:bridge:gemini'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :gemini)
    end
  end
end
