# frozen_string_literal: true

require 'open3'
require 'spec_helper'

RSpec.describe 'rails_ai_bridge standalone load' do
  # Pin the gem's own Gemfile and cwd so host shell state cannot leak in.
  let(:project_root) { File.expand_path('../..', __dir__) }
  let(:subprocess_env) { ENV.to_h.merge('BUNDLE_GEMFILE' => File.join(project_root, 'Gemfile')) }

  it 'loads without a full Rails environment' do
    command = ['bundle', 'exec', 'ruby', '-Ilib', '-e', "require 'rails_ai_bridge'; puts RailsAiBridge::VERSION"]
    stdout, stderr, status = Open3.capture3(subprocess_env, *command, chdir: project_root)

    aggregate_failures do
      expect(status).to be_success, "expected standalone require to succeed, got exit #{status.exitstatus}\nstderr: #{stderr}\nstdout: #{stdout}"
      expect(stdout.chomp).to eq(RailsAiBridge::VERSION)
    end
  end
end
