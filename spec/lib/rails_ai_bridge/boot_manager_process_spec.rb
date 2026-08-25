# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'timeout'

RSpec.describe RailsAiBridge::BootManager do
  let(:boot_script) do
    <<~RUBY
      require 'rails'
      require 'active_record'
      require 'bundler'
      require 'rails_ai_bridge'

      result = RailsAiBridge::BootManager.boot(ARGV.fetch(0), timeout: Float(ARGV.fetch(1)))
      puts JSON.generate(result.except(:app))
    RUBY
  end

  def boot_fixture(name, timeout: 1)
    root = File.expand_path("../../fixtures/boot_apps/#{name}", __dir__)
    lib = File.expand_path('../../../lib', __dir__)
    stdout, stderr, status = Timeout.timeout(10) do
      Open3.capture3(RbConfig.ruby, '-I', lib, '-rjson', '-e', boot_script, root, timeout.to_s)
    end
    expect(status).to be_success, stderr

    [JSON.parse(stdout, symbolize_names: true), stderr, status]
  end

  describe '.boot in an isolated process' do
    {
      syntax_error: 'SyntaxError',
      timeout: 'Timeout::Error',
      database_outage: 'ActiveRecord::ConnectionNotEstablished',
      version_conflict: 'Gem::LoadError',
      missing_bundle: 'Bundler::GemNotFound'
    }.each do |fixture, error_class|
      it "captures a #{fixture.to_s.tr('_', ' ')} boot exception" do
        timeout = fixture == :timeout ? 0.5 : 2
        result, _stderr, status = boot_fixture(fixture, timeout: timeout)

        expect(status).to be_success
        expect(result).to include(
          success: false,
          error_class: error_class,
          stdout_quarantined: true
        )
      end
    end

    it 'keeps boot noise off stdout' do
      result, stderr, status = boot_fixture(:stdout_noise)

      expect(status).to be_success
      expect(result).to include(success: false, error_class: 'RuntimeError')
      expect(stderr).to include('boot noise')
    end
  end
end
