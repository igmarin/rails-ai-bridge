# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'rails_ai_bridge rake tasks' do
  let(:rake) { Rake.application }
  let(:task_path) { File.expand_path('../../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake', __dir__) }
  let(:result) { { written: [], skipped: [] } }
  let!(:original_context_mode) { RailsAiBridge.configuration.context_mode }
  let!(:original_managed_region) { RailsAiBridge.configuration.managed_region }
  let!(:original_rake_application) { Rake.application }

  before do
    # Ensure ENV keys that affect rake tasks start in a known state
    ENV.delete('FORMAT')
    ENV.delete('CONFIRM')
    ENV.delete('CONTEXT_MODE')
    ENV.delete('CHECK')
    ENV.delete('MERGE')

    # Setup new Rake application for each test to avoid state leakage
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load task_path

    rake.tasks.each(&:reenable)
    allow(RailsAiBridge).to receive(:generate_context).and_return(result)
  end

  after do
    # Restore original Rake application and clean up ENV mutations
    Rake.application = original_rake_application
    RailsAiBridge.configuration.context_mode = original_context_mode
    RailsAiBridge.configuration.managed_region = original_managed_region
    ENV.delete('FORMAT')
    ENV.delete('CONFIRM')
    ENV.delete('CONTEXT_MODE')
    ENV.delete('CHECK')
    ENV.delete('MERGE')
  end

  describe 'MERGE env var' do
    it 'turns managed regions on for ai:bridge' do
      ENV['MERGE'] = '1'
      expect { rake['ai:bridge'].invoke }.to output(/Managed region: on/).to_stdout
      expect(RailsAiBridge.configuration.managed_region).to be true
    end

    it 'turns managed regions off when explicitly disabled' do
      RailsAiBridge.configuration.managed_region = true
      ENV['MERGE'] = '0'
      expect { rake['ai:bridge'].invoke }.to output(/Managed region: off/).to_stdout
      expect(RailsAiBridge.configuration.managed_region).to be false
    end

    it 'leaves the configured value alone when unset' do
      RailsAiBridge.configuration.managed_region = true
      rake['ai:bridge'].invoke
      expect(RailsAiBridge.configuration.managed_region).to be true
    end

    it 'applies to per-format tasks' do
      ENV['MERGE'] = 'true'
      rake['ai:bridge:claude'].invoke
      expect(RailsAiBridge.configuration.managed_region).to be true
    end

    it 'stays off when MERGE=0 and config is already false' do
      ENV['MERGE'] = '0'
      expect { rake['ai:bridge'].invoke }.to output(/Managed region: off/).to_stdout
      expect(RailsAiBridge.configuration.managed_region).to be false
    end
  end

  describe 'ai:bridge' do
    it 'calls generate_context with the :all format' do
      rake['ai:bridge'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all, split_rules: true, on_conflict: :overwrite)
    end

    it 'prints written and skipped files' do
      result[:written] = ['/foo/CLAUDE.md']
      result[:skipped] = ['/foo/.cursorrules']

      expect { rake['ai:bridge'].invoke }.to output(%r{✅ /foo/CLAUDE\.md.*⏭️  /foo/\.cursorrules \(unchanged\)}m).to_stdout
    end
  end

  describe 'ai:bridge_for' do
    it 'calls generate_context with the specified format' do
      rake['ai:bridge_for'].invoke('cursor')
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :cursor, split_rules: true, on_conflict: :overwrite)
    end

    it 'calls generate_context with format from ENV' do
      ENV['FORMAT'] = 'codex'
      rake['ai:bridge_for'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :codex, split_rules: true, on_conflict: :overwrite)
    ensure
      ENV.delete('FORMAT')
    end

    it 'defaults to claude when no format is specified' do
      ENV.delete('FORMAT') # Ensure no ENV variable is interfering
      rake['ai:bridge_for'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :claude, split_rules: true, on_conflict: :overwrite)
    end

    it 'passes unknown formats as symbols' do
      ENV['FORMAT'] = 'unknown_format_xyz'
      rake['ai:bridge_for'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :unknown_format_xyz, split_rules: true, on_conflict: :overwrite)
    ensure
      ENV.delete('FORMAT')
    end
  end

  describe 'ai:bridge:full' do
    it 'sets context_mode to :full and calls generate_context with :all' do
      rake['ai:bridge:full'].invoke
      expect(RailsAiBridge.configuration.context_mode).to eq(:full)
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :all, split_rules: true, on_conflict: :overwrite)
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

      expect { rake['ai:inspect'].invoke }.to output(
        /TestApp — AI Context Summary.*Rails 7\.1\.3 \| Ruby 3\.3\.0.*📦 Database: 5 tables \(postgresql\).*🏗️  Models: 2.*🛤️  Routes: 10.*🏛️  Architecture: Service Objects/m
      ).to_stdout
    end

    it 'handles introspection errors gracefully' do
      allow(RailsAiBridge).to receive(:introspect).and_return({
                                                                app_name: 'TestApp',
                                                                rails_version: '7.1.3',
                                                                ruby_version: '3.3.0',
                                                                schema: { error: 'DB connection failed' }
                                                              })

      expect { rake['ai:inspect'].invoke }.to output(/TestApp — AI Context Summary/).to_stdout
      rake['ai:inspect'].reenable
      expect { rake['ai:inspect'].invoke }.not_to output(/📦 Database/).to_stdout
    end
  end

  describe 'ai:doctor' do
    it 'runs diagnostic checks' do
      doctor_result = { score: 100, checks: [double(name: 'Check1', message: 'OK', status: :pass, fix: nil)] }
      doctor_instance = double('Doctor', run: doctor_result)
      allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

      expect { rake['ai:doctor'].invoke }.to output(
        %r{🩺 Running AI readiness diagnostics\.\.\..*✅ Check1: OK.*AI Readiness Score: 100/100}m
      ).to_stdout
    end
  end

  # New test for gemini
  describe 'ai:bridge:gemini' do
    it 'calls generate_context with the :gemini format' do
      rake['ai:bridge:gemini'].invoke
      expect(RailsAiBridge).to have_received(:generate_context).with(format: :gemini, split_rules: true, on_conflict: :overwrite)
    end
  end

  describe 'ai:check' do
    context 'when checks pass or warn' do
      it 'outputs results and exits normally' do
        doctor_result = {
          score: 80,
          checks: [
            double(name: 'CheckPass', message: 'Passed check', status: :pass, fix: nil),
            double(name: 'CheckWarn', message: 'Warning check', status: :warn, fix: 'Fix this warn')
          ]
        }
        doctor_instance = double('Doctor', run: doctor_result)
        allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

        expect { rake['ai:check'].invoke }.to output(
          %r{🩺 Running AI readiness diagnostics\.\.\..*✅ CheckPass: Passed check.*⚠️  CheckWarn: Warning check.*AI Readiness Score: 80/100.*✅ Diagnostics passed\.}m
        ).to_stdout
      end
    end

    context 'when a check fails' do
      it 'exits with exit code 1' do
        doctor_result = {
          score: 40,
          checks: [
            double(name: 'CheckFail', message: 'Failed check', status: :fail, fix: 'Fix this fail')
          ]
        }
        doctor_instance = double('Doctor', run: doctor_result)
        allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

        expect { rake['ai:check'].invoke }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end

  describe 'CHECK=1 integration' do
    before do
      ENV['CHECK'] = '1'
    end

    after do
      ENV.delete('CHECK')
    end

    context 'when checks pass' do
      it 'proceeds to run context generation' do
        doctor_result = {
          score: 100,
          checks: [double(name: 'CheckPass', message: 'Passed check', status: :pass, fix: nil)]
        }
        doctor_instance = double('Doctor', run: doctor_result)
        allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

        expect { rake['ai:bridge'].invoke }.to output(/Proceeding with file generation/).to_stdout
        expect(RailsAiBridge).to have_received(:generate_context)
      end
    end

    context 'when a check fails' do
      it 'aborts and does not run context generation' do
        doctor_result = {
          score: 50,
          checks: [double(name: 'CheckFail', message: 'Failed check', status: :fail, fix: 'Fix this')]
        }
        doctor_instance = double('Doctor', run: doctor_result)
        allow(RailsAiBridge::Doctor).to receive(:new).and_return(doctor_instance)

        expect { rake['ai:bridge'].invoke }.to raise_error(SystemExit)
        expect(RailsAiBridge).not_to have_received(:generate_context)
      end
    end
  end

  describe 'ai:registry:validate' do
    # The top-level group already defines six memoized helpers — the
    # RSpec/MultipleMemoizedHelpers limit — so this block manages the manifest
    # path with an `around` hook and a helper method instead of `let`s or
    # instance variables (which RSpec/InstanceVariable forbids).
    around do |example|
      registry = RailsAiBridge.configuration.registry
      original_path = registry.registry_manifest_path
      tmp_dir = Dir.mktmpdir
      registry.registry_manifest_path = File.join(tmp_dir, 'registry.json')

      example.run
    ensure
      registry.registry_manifest_path = original_path
      FileUtils.rm_rf(tmp_dir)
    end

    def manifest_path
      RailsAiBridge.configuration.registry.registry_manifest_path
    end

    context 'when the manifest is valid' do
      before do
        File.write(manifest_path, JSON.generate({
                                                  'version' => '1.0.0',
                                                  'packs' => { 'core' => { 'source' => 'igmarin/ruby-core-skills' } },
                                                  'default_stack' => %w[core]
                                                }))
      end

      it 'reports success with version and pack count' do
        expect { rake['ai:registry:validate'].invoke }
          .to output(/is valid \(version: 1\.0\.0, packs: 1\)/).to_stdout
      end
    end

    context 'when the manifest is structurally invalid' do
      before do
        File.write(manifest_path, JSON.generate({
                                                  'version' => '1.0.0',
                                                  'packs' => { 'core' => { 'source' => '' } }
                                                }))
      end

      it 'prints the validation error to stderr and exits 1' do
        expect { rake['ai:registry:validate'].invoke }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(/validation failed.*source.*non-empty/m).to_stderr
      end
    end

    context 'when the manifest file does not exist' do
      it 'reports the missing file and exits 1' do
        expect { rake['ai:registry:validate'].invoke }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(/not found/).to_stderr
      end
    end

    context 'when the manifest contains invalid JSON' do
      before do
        File.write(manifest_path, '{ not valid json }')
      end

      it 'reports the parse error and exits 1' do
        expect { rake['ai:registry:validate'].invoke }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(/invalid JSON/).to_stderr
      end
    end
  end

  describe 'ai:skills:list output formats' do
    # No memoized helpers here: the top-level group already defines six,
    # which is the RSpec/MultipleMemoizedHelpers limit.
    before do
      resolver = instance_double(RailsAiBridge::Registry::Resolver)
      allow(RailsAiBridge::Registry).to receive(:build_resolver).and_return(resolver)
      allow(resolver).to receive_messages(
        list_skills: [
          RailsAiBridge::Registry::SkillSummary.new(name: 'code-review', pack: 'rails', description: 'Review code.')
        ],
        active_packs: []
      )
    end

    it 'prints the human-readable table by default' do
      expect { rake['ai:skills:list'].invoke }.to output(/Available Skills \(1\)/).to_stdout
    end

    it 'prints a parseable JSON document for the json format argument' do
      json = capture_stdout { rake['ai:skills:list'].invoke('json') }
      parsed = JSON.parse(json)

      expect(parsed.keys).to contain_exactly('packs', 'skills')
      expect(parsed['skills'].first['name']).to eq('code-review')
    end

    it 'prints JSON when FORMAT=json is set' do
      ENV['FORMAT'] = 'json'
      json = capture_stdout { rake['ai:skills:list'].invoke }

      expect { JSON.parse(json) }.not_to raise_error
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end
end
