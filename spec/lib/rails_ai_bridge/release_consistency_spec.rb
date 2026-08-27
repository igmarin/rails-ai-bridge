# frozen_string_literal: true

require 'spec_helper'

# Guard spec that prevents version drift between RailsAiBridge::VERSION and the
# files that must agree with it: CHANGELOG.md's latest released version heading
# and the rails-ai-bridge entries in the lockfiles. The release workflow
# extracts GitHub Release notes from the "## [<version>]" heading and silently
# falls back to a generic body when the section is missing; this spec fails in
# CI before that happens.
RSpec.describe 'release consistency between VERSION and version-bearing files' do
  let(:changelog) { File.read(File.expand_path('../../../CHANGELOG.md', __dir__)) }

  it 'matches the latest released version heading in CHANGELOG.md' do
    released = changelog[/^## \[(\d+\.\d+\.\d+)\]/, 1]

    expect(released).not_to be_nil,
                            'CHANGELOG.md must contain at least one released ' \
                            '"## [x.y.z]" heading'

    expect(released).to eq(RailsAiBridge::VERSION),
                        "CHANGELOG.md latest released version is #{released.inspect} but " \
                        "RailsAiBridge::VERSION is #{RailsAiBridge::VERSION.inspect}. " \
                        'Update lib/rails_ai_bridge/version.rb or the CHANGELOG so they match.'
  end

  it 'keeps the lockfile rails-ai-bridge entries in sync' do
    %w[Gemfile.lock Gemfile-mutation.lock].each do |lockfile|
      content = File.read(File.expand_path("../../../#{lockfile}", __dir__))
      expected = "rails-ai-bridge (#{RailsAiBridge::VERSION})"
      declared = content[/rails-ai-bridge \([\d.]+\)/]

      expect(content).to include(expected),
                         "#{lockfile} must declare #{expected.inspect} but declares " \
                         "#{declared.inspect}. Regenerate the lockfile after a version bump."
    end
  end
end
