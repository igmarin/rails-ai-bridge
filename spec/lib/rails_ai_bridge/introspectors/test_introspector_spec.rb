# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::TestIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns framework as a known string' do
      expect(result[:framework]).to be_in(%w[rspec minitest unknown])
    end

    it 'returns CI config as array' do
      expect(result[:ci_config]).to be_an(Array)
    end

    it 'returns test_helpers as array' do
      expect(result[:test_helpers]).to be_an(Array)
    end

    it 'returns nil for factories when none exist' do
      expect(result[:factories]).to be_nil
    end

    it 'returns nil for fixtures when none exist' do
      expect(result[:fixtures]).to be_nil
    end

    it 'returns nil for system_tests when none exist' do
      expect(result[:system_tests]).to be_nil
    end

    it 'returns nil for vcr_cassettes when none exist' do
      expect(result[:vcr_cassettes]).to be_nil
    end

    it 'returns nil for coverage when no Gemfile.lock' do
      expect(result[:coverage]).to be_nil
    end

    context 'with a spec directory' do
      let(:spec_dir) { Rails.root.join('spec').to_s }
      let!(:spec_existed) { File.directory?(spec_dir) }

      before { FileUtils.mkdir_p(spec_dir) }
      after { FileUtils.rmdir(spec_dir) if !spec_existed && File.directory?(spec_dir) && Dir.empty?(spec_dir) }

      it 'detects rspec framework' do
        expect(result[:framework]).to eq('rspec')
      end
    end

    context 'with a test directory' do
      let(:test_dir) { Rails.root.join('test').to_s }
      let!(:test_existed) { File.directory?(test_dir) }

      before { FileUtils.mkdir_p(test_dir) }
      after { FileUtils.rmdir(test_dir) if !test_existed && File.directory?(test_dir) && Dir.empty?(test_dir) }

      it 'detects minitest framework' do
        # Ensure spec/ doesn't exist (rspec takes priority)
        spec_dir = Rails.root.join('spec').to_s
        had_spec = Dir.exist?(spec_dir)
        expect(result[:framework]).to eq(had_spec ? 'rspec' : 'minitest')
      end
    end

    context 'with factories' do
      let(:factories_dir) { Rails.root.join('spec/factories').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(factories_dir)
        File.write(File.join(factories_dir, 'users.rb'), 'FactoryBot.define {}')
      end

      after do
        FileUtils.rm_rf(factories_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects factories with location and count' do
        expect(result[:factories]).to be_a(Hash)
        expect(result[:factories][:location]).to eq('spec/factories')
        expect(result[:factories][:count]).to eq(1)
      end
    end

    context 'with test/factories (not spec/factories)' do
      let(:factories_dir) { Rails.root.join('test/factories').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(factories_dir)
        File.write(File.join(factories_dir, 'users.rb'), 'FactoryBot.define {}')
      end

      after do
        FileUtils.rm_rf(factories_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects factories in test/factories' do
        expect(result[:factories]).to be_a(Hash)
        expect(result[:factories][:location]).to eq('test/factories')
        expect(result[:factories][:count]).to eq(1)
      end
    end

    context 'with empty spec/factories (count zero)' do
      let(:factories_dir) { Rails.root.join('spec/factories').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before { FileUtils.mkdir_p(factories_dir) }

      after do
        FileUtils.rm_rf(factories_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'returns nil for factories when directory is empty' do
        expect(result[:factories]).to be_nil
      end
    end

    context 'with fixtures' do
      let(:fixtures_dir) { Rails.root.join('spec/fixtures').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(fixtures_dir)
        File.write(File.join(fixtures_dir, 'users.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(fixtures_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects fixtures with location and count' do
        expect(result[:fixtures]).to be_a(Hash)
        expect(result[:fixtures][:location]).to eq('spec/fixtures')
        expect(result[:fixtures][:count]).to eq(1)
      end
    end

    context 'with test/fixtures (not spec/fixtures)' do
      let(:fixtures_dir) { Rails.root.join('test/fixtures').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(fixtures_dir)
        File.write(File.join(fixtures_dir, 'users.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(fixtures_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects fixtures in test/fixtures' do
        expect(result[:fixtures]).to be_a(Hash)
        expect(result[:fixtures][:location]).to eq('test/fixtures')
      end
    end

    context 'with empty spec/fixtures (count zero)' do
      let(:fixtures_dir) { Rails.root.join('spec/fixtures').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before { FileUtils.mkdir_p(fixtures_dir) }

      after do
        FileUtils.rm_rf(fixtures_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'returns nil for fixtures when directory is empty' do
        expect(result[:fixtures]).to be_nil
      end
    end

    context 'with system tests' do
      let(:system_dir) { Rails.root.join('spec/system').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(system_dir)
        File.write(File.join(system_dir, 'login_test.rb'), 'require "test_helper"')
      end

      after do
        FileUtils.rm_rf(system_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects system tests with location and count' do
        expect(result[:system_tests]).to be_a(Hash)
        expect(result[:system_tests][:location]).to eq('spec/system')
        expect(result[:system_tests][:count]).to eq(1)
      end
    end

    context 'with test/system (not spec/system)' do
      let(:system_dir) { Rails.root.join('test/system').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(system_dir)
        File.write(File.join(system_dir, 'login_test.rb'), 'require "test_helper"')
      end

      after do
        FileUtils.rm_rf(system_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects system tests in test/system' do
        expect(result[:system_tests]).to be_a(Hash)
        expect(result[:system_tests][:location]).to eq('test/system')
      end
    end

    context 'with empty spec/system (count zero)' do
      let(:system_dir) { Rails.root.join('spec/system').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before { FileUtils.mkdir_p(system_dir) }

      after do
        FileUtils.rm_rf(system_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'returns nil for system_tests when directory is empty' do
        expect(result[:system_tests]).to be_nil
      end
    end

    context 'with test helpers' do
      let(:support_dir) { Rails.root.join('spec/support').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(support_dir)
        File.write(File.join(support_dir, 'auth_helper.rb'), 'module AuthHelper; end')
      end

      after do
        FileUtils.rm_rf(support_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects test helpers from spec/support' do
        expect(result[:test_helpers]).to include('spec/support/auth_helper.rb')
      end
    end

    context 'with test/helpers (not spec/support)' do
      let(:helpers_dir) { Rails.root.join('test/helpers').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(helpers_dir)
        File.write(File.join(helpers_dir, 'auth_helper.rb'), 'module AuthHelper; end')
      end

      after do
        FileUtils.rm_rf(helpers_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects test helpers from test/helpers' do
        expect(result[:test_helpers]).to include('test/helpers/auth_helper.rb')
      end
    end

    context 'with VCR cassettes in spec/cassettes' do
      let(:cassettes_dir) { Rails.root.join('spec/cassettes').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(cassettes_dir)
        File.write(File.join(cassettes_dir, 'api.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(cassettes_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects VCR cassettes with location and count' do
        expect(result[:vcr_cassettes]).to be_a(Hash)
        expect(result[:vcr_cassettes][:location]).to eq('spec/cassettes')
        expect(result[:vcr_cassettes][:count]).to eq(1)
      end
    end

    context 'with VCR cassettes in spec/vcr_cassettes' do
      let(:cassettes_dir) { Rails.root.join('spec/vcr_cassettes').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before do
        FileUtils.mkdir_p(cassettes_dir)
        File.write(File.join(cassettes_dir, 'api.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(cassettes_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'detects VCR cassettes in spec/vcr_cassettes' do
        expect(result[:vcr_cassettes]).to be_a(Hash)
        expect(result[:vcr_cassettes][:location]).to eq('spec/vcr_cassettes')
      end
    end

    context 'with VCR cassettes in test/cassettes' do
      let(:cassettes_dir) { Rails.root.join('test/cassettes').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(cassettes_dir)
        File.write(File.join(cassettes_dir, 'api.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(cassettes_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects VCR cassettes in test/cassettes' do
        expect(result[:vcr_cassettes]).to be_a(Hash)
        expect(result[:vcr_cassettes][:location]).to eq('test/cassettes')
      end
    end

    context 'with VCR cassettes in test/vcr_cassettes' do
      let(:cassettes_dir) { Rails.root.join('test/vcr_cassettes').to_s }
      let!(:test_existed) { Rails.root.join('test').directory? }

      before do
        FileUtils.mkdir_p(cassettes_dir)
        File.write(File.join(cassettes_dir, 'api.yml'), "name: test\n")
      end

      after do
        FileUtils.rm_rf(cassettes_dir)
        FileUtils.rmdir(Rails.root.join('test').to_s) if !test_existed && Rails.root.join('test').directory? && Dir.empty?(Rails.root.join('test').to_s)
      end

      it 'detects VCR cassettes in test/vcr_cassettes' do
        expect(result[:vcr_cassettes]).to be_a(Hash)
        expect(result[:vcr_cassettes][:location]).to eq('test/vcr_cassettes')
      end
    end

    context 'with empty spec/cassettes (count zero)' do
      let(:cassettes_dir) { Rails.root.join('spec/cassettes').to_s }
      let!(:spec_existed) { Rails.root.join('spec').directory? }

      before { FileUtils.mkdir_p(cassettes_dir) }

      after do
        FileUtils.rm_rf(cassettes_dir)
        FileUtils.rmdir(Rails.root.join('spec').to_s) if !spec_existed && Rails.root.join('spec').directory? && Dir.empty?(Rails.root.join('spec').to_s)
      end

      it 'returns nil for vcr_cassettes when directory is empty' do
        expect(result[:vcr_cassettes]).to be_nil
      end
    end

    context 'with CI configs' do
      let(:github_dir) { Rails.root.join('.github/workflows').to_s }
      let(:circleci_dir) { Rails.root.join('.circleci').to_s }
      let(:gitlab_file) { Rails.root.join('.gitlab-ci.yml').to_s }
      let(:travis_file) { Rails.root.join('.travis.yml').to_s }
      let!(:ci_existed) do
        { github: Rails.root.join('.github').directory?, circleci: Rails.root.join('.circleci').directory? }
      end

      before do
        FileUtils.mkdir_p(github_dir)
        File.write(File.join(github_dir, 'ci.yml'), 'name: CI')
        FileUtils.mkdir_p(circleci_dir)
        File.write(File.join(circleci_dir, 'config.yml'), 'version: 2')
        File.write(gitlab_file, "stages:\n  - test")
        File.write(travis_file, 'language: ruby')
      end

      after do
        github_root = Rails.root.join('.github')
        FileUtils.rm_rf(github_dir)
        FileUtils.rmdir(github_root.to_s) if !ci_existed[:github] && github_root.directory? && Dir.empty?(github_root.to_s)
        FileUtils.rm_rf(circleci_dir) unless ci_existed[:circleci]
        FileUtils.rm_f(gitlab_file)
        FileUtils.rm_f(travis_file)
      end

      it 'detects all CI configurations' do
        expect(result[:ci_config]).to include('github_actions')
        expect(result[:ci_config]).to include('circleci')
        expect(result[:ci_config]).to include('gitlab_ci')
        expect(result[:ci_config]).to include('travis')
      end
    end

    context 'with Gemfile.lock containing reek' do
      let(:gemfile_lock) { Rails.root.join('Gemfile.lock').to_s }
      let!(:original_content) { File.exist?(gemfile_lock) ? File.read(gemfile_lock) : nil }

      before { File.write(gemfile_lock, "reek (6.3.0)\n") }

      after do
        if original_content
          File.write(gemfile_lock, original_content)
        else
          FileUtils.rm_f(gemfile_lock)
        end
      end

      it 'detects reek coverage tool' do
        expect(result[:coverage]).to eq('reek')
      end
    end

    context 'with Gemfile.lock without reek' do
      let(:gemfile_lock) { Rails.root.join('Gemfile.lock').to_s }
      let!(:original_content) { File.exist?(gemfile_lock) ? File.read(gemfile_lock) : nil }

      before { File.write(gemfile_lock, "rails (7.1.0)\n") }

      after do
        if original_content
          File.write(gemfile_lock, original_content)
        else
          FileUtils.rm_f(gemfile_lock)
        end
      end

      it 'returns nil for coverage when reek is not present' do
        expect(result[:coverage]).to be_nil
      end
    end

    context 'when app.root raises an error' do
      let(:bad_app) { double('Rails::Application') }

      before { allow(bad_app).to receive(:root).and_raise(StandardError, 'root boom') }

      it 'returns error hash' do
        expect(described_class.new(bad_app).call[:error]).to eq('root boom')
      end
    end
  end
end
